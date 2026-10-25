library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_math;
use nsl_amba.axi4_mm.all;
use nsl_amba.axi_m2m_dma.all;
use nsl_amba.dma_request.all;
use nsl_amba.axi_m2m_dma_priv.all;
use nsl_data.bytestream.all;

-- Read side of axi_m2m_microcoded_dma.
--
-- One read burst at a time: either an instruction fetch (one bus
-- word) or a load.  Loads go first, they never wait for anything but
-- the bus.  A load is taken from a one-entry slot, split in two bursts
-- when crossing a 4 kB boundary.  Every read beat carries a known
-- span of bytes (lanes lo to lo + n - 1); the beat is registered, then
-- its bytes are written to the MFIFO lanes at the channel's write
-- pointer on the next cycle.  Loads of an aborted channel are dropped,
-- or, if in flight, completed without writing the MFIFO.
--
-- A load burst answered with an error still writes its bytes to the
-- MFIFO.  With failed_store_fault_c, the stream position its bytes
-- start at, the channel's first such, is published (poison_o,
-- poisoned_o) until the channel's MFIFO is cleared: the thread engine
-- faults a store reaching it.
entity axi_m2m_dma_reader is
  generic(
    config_c : nsl_amba.axi4_mm.config_t;
    channel_count_c : positive;
    mfifo_depth_l2_c : positive;
    failed_store_fault_c : boolean
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    ar_o : out nsl_amba.axi4_mm.address_t;
    ar_i : in nsl_amba.axi4_mm.handshake_t;
    r_o : out nsl_amba.axi4_mm.handshake_t;
    r_i : in nsl_amba.axi4_mm.read_data_t;

    fetch_i : in fetch_request_t;
    fetch_ready_o : out std_ulogic;
    fetch_o : out fetch_response_t;

    load_i : in transfer_t;
    load_ready_o : out std_ulogic;

    busy_o : out std_ulogic_vector(0 to channel_count_c-1);
    error_o : out std_ulogic_vector(0 to channel_count_c-1);
    abort_i : in std_ulogic_vector(0 to channel_count_c-1);
    clear_i : in std_ulogic_vector(0 to channel_count_c-1);
    pushed_o : out ptr_vector(0 to channel_count_c-1);
    poisoned_o : out std_ulogic_vector(0 to channel_count_c-1);
    poison_o : out ptr_vector(0 to channel_count_c-1);

    mfifo_address_o : out lane_addr_vector(0 to 2**config_c.data_bus_width_l2-1);
    mfifo_enable_o : out std_ulogic_vector(0 to 2**config_c.data_bus_width_l2-1);
    mfifo_data_o : out byte_string(0 to 2**config_c.data_bus_width_l2-1);

    ack_o : out ack_request_t;
    ack_grant_i : in std_ulogic
    );
end entity;

architecture beh of axi_m2m_dma_reader is

  constant bus_l2_c : natural := config_c.data_bus_width_l2;
  constant bus_bytes_c : natural := 2**bus_l2_c;
  constant word_l2_c : natural := mfifo_depth_l2_c;
  constant cap_l2_c : natural := mfifo_depth_l2_c + bus_l2_c;

  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_FETCH_AR,
    ST_FETCH_R,
    ST_LD_PREP,
    ST_LD_AR,
    ST_LD_R,
    ST_LD_NEXT,
    ST_LD_ACK
    );

  type regs_t is
  record
    state: state_t;
    slot: transfer_t;
    cmd: transfer_t;
    fetch: fetch_request_t;
    rsp: fetch_response_t;

    -- Current burst
    addr: unsigned(31 downto 0);
    part_m1: unsigned(3 downto 0);
    split: std_ulogic;

    -- Span of the next beat
    lo: unsigned(bus_l2_c-1 downto 0);
    n: unsigned(max_bus_bytes_l2_c downto 0);

    -- Beat waiting to be pushed to the MFIFO
    push_valid: std_ulogic;
    push_data: byte_string(0 to bus_bytes_c-1);
    push_lo: unsigned(bus_l2_c-1 downto 0);
    push_n: unsigned(max_bus_bytes_l2_c downto 0);

    -- Write pointer of the current load channel
    wp: ptr_t;
    wptr: ptr_vector(0 to channel_count_c-1);
    -- Write pointer at the start of the current burst
    burst_wp: ptr_t;
    -- Per channel: a failed load's bytes start at poison
    poisoned: std_ulogic_vector(0 to channel_count_c-1);
    poison: ptr_vector(0 to channel_count_c-1);

    error: std_ulogic_vector(0 to channel_count_c-1);
    ack: ack_request_t;
  end record;

  signal r, rin: regs_t;

  function channel_id(ch : channel_t) return std_ulogic_vector is
  begin
    return std_ulogic_vector(resize(ch, config_c.id_width));
  end function;

  -- The manager thread's ID is the channel count, as the DMA-330's.
  function fetch_id(f : fetch_request_t) return std_ulogic_vector is
  begin
    if f.manager = '1' then
      return std_ulogic_vector(to_unsigned(channel_count_c, config_c.id_width));
    end if;
    return channel_id(f.channel);
  end function;

  function is_aborted(abort : std_ulogic_vector; ch : channel_t) return boolean is
  begin
    for c in abort'range
    loop
      if ch = to_unsigned(c, ch'length) then
        return abort(c) = '1';
      end if;
    end loop;
    return false;
  end function;

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_RESET;
      r.slot.valid <= '0';
      r.rsp.valid <= '0';
      r.push_valid <= '0';
      r.error <= (others => '0');
      r.poisoned <= (others => '0');
      r.ack.valid <= '0';
    end if;
  end process;

  transition: process(r, ar_i, r_i, fetch_i, load_i, abort_i, clear_i, ack_grant_i) is
    variable page_m1 : unsigned(11 downto 0);
    variable pushed : ptr_t;
  begin
    rin <= r;

    rin.rsp.valid <= '0';
    rin.error <= (others => '0');
    rin.push_valid <= '0';

    page_m1 := shift_right(not r.cmd.addr(11 downto 0), to_integer(r.cmd.size_l2));
    pushed := ptr_wrap(r.wp + r.push_n, cap_l2_c);

    if r.slot.valid = '0' and load_i.valid = '1' then
      rin.slot <= load_i;
    end if;

    if r.push_valid = '1' then
      rin.wp <= pushed;
      for c in 0 to channel_count_c-1
      loop
        if r.cmd.channel = to_unsigned(c, channel_t'length) then
          rin.wptr(c) <= pushed;
        end if;
      end loop;
    end if;

    case r.state is
      when ST_RESET =>
        rin.wptr <= (others => (others => '0'));
        rin.state <= ST_IDLE;

      when ST_IDLE =>
        if r.slot.valid = '1' then
          if r.push_valid = '0' then
            rin.slot.valid <= '0';
            rin.cmd <= r.slot;
            for c in 0 to channel_count_c-1
            loop
              if r.slot.channel = to_unsigned(c, channel_t'length) then
                rin.wp <= r.wptr(c);
              end if;
            end loop;
            if not is_aborted(abort_i, r.slot.channel) then
              rin.state <= ST_LD_PREP;
            end if;
          end if;
        elsif fetch_i.valid = '1' then
          rin.fetch <= fetch_i;
          rin.state <= ST_FETCH_AR;
        end if;

      when ST_FETCH_AR =>
        if is_ready(config_c, ar_i) then
          rin.state <= ST_FETCH_R;
        end if;

      when ST_FETCH_R =>
        if is_valid(config_c, r_i) then
          rin.rsp.valid <= '1';
          rin.rsp.data(0 to bus_bytes_c-1) <= bytes(config_c, r_i);
          if resp(config_c, r_i) = RESP_OKAY then
            rin.rsp.error <= '0';
          else
            rin.rsp.error <= '1';
          end if;
          if is_last(config_c, r_i) then
            rin.state <= ST_IDLE;
          end if;
        end if;

      when ST_LD_PREP =>
        rin.burst_wp <= r.wp;
        rin.addr <= r.cmd.addr;
        rin.lo <= r.cmd.addr(bus_l2_c-1 downto 0);
        rin.n <= size_bytes(r.cmd.size_l2)
                 - resize(r.cmd.addr(max_bus_bytes_l2_c-1 downto 0) and size_mask(r.cmd.size_l2), max_bus_bytes_l2_c+1);
        if r.cmd.incr = '1' and page_m1 < resize(r.cmd.len_m1, 12) then
          rin.part_m1 <= page_m1(3 downto 0);
          rin.split <= '1';
        else
          rin.part_m1 <= r.cmd.len_m1;
          rin.split <= '0';
        end if;
        rin.state <= ST_LD_AR;

      when ST_LD_AR =>
        if is_ready(config_c, ar_i) then
          rin.state <= ST_LD_R;
        end if;

      when ST_LD_R =>
        if is_valid(config_c, r_i) then
          rin.push_valid <= not abort_i(to_integer(r.cmd.channel));
          rin.push_data <= bytes(config_c, r_i);
          rin.push_lo <= r.lo;
          rin.push_n <= r.n;
          if r.cmd.incr = '1' then
            rin.lo <= (r.lo and not size_mask(r.cmd.size_l2)(bus_l2_c-1 downto 0))
                      + resize(size_bytes(r.cmd.size_l2), bus_l2_c);
            rin.n <= size_bytes(r.cmd.size_l2);
          end if;

          if resp(config_c, r_i) /= RESP_OKAY then
            rin.error(to_integer(r.cmd.channel)) <= '1';
            if failed_store_fault_c and r.poisoned(to_integer(r.cmd.channel)) = '0' then
              rin.poisoned(to_integer(r.cmd.channel)) <= '1';
              rin.poison(to_integer(r.cmd.channel)) <= r.burst_wp;
            end if;
          end if;

          if is_last(config_c, r_i) then
            if r.split = '1' then
              rin.state <= ST_LD_NEXT;
            elsif r.cmd.ack = '1' then
              rin.ack.valid <= '1';
              rin.ack.periph <= r.cmd.periph;
              if r.cmd.ack_burst = '1' then
                rin.ack.atype <= datype_burst_c;
              else
                rin.ack.atype <= datype_single_c;
              end if;
              rin.state <= ST_LD_ACK;
            else
              rin.state <= ST_IDLE;
            end if;
          end if;
        end if;

      when ST_LD_NEXT =>
        -- The first part's last beat is pushed this cycle
        rin.burst_wp <= pushed;
        rin.addr <= (r.addr(31 downto 12) + 1) & x"000";
        rin.part_m1 <= r.cmd.len_m1 + not r.part_m1;
        rin.split <= '0';
        rin.state <= ST_LD_AR;

      when ST_LD_ACK =>
        if ack_grant_i = '1' then
          rin.ack.valid <= '0';
          rin.state <= ST_IDLE;
        end if;
    end case;

    for c in 0 to channel_count_c-1
    loop
      if clear_i(c) = '1' then
        rin.wptr(c) <= (others => '0');
        rin.poisoned(c) <= '0';
      end if;
    end loop;
  end process;

  moore: process(r) is
    variable k : unsigned(bus_l2_c-1 downto 0);
    variable word : unsigned(word_l2_c-1 downto 0);
    variable lane_addr : unsigned(word_l2_c+2 downto 0);
  begin
    ar_o <= address_defaults(config_c);
    case r.state is
      when ST_FETCH_AR =>
        ar_o <= address(config_c,
                        id => fetch_id(r.fetch),
                        addr => r.fetch.addr,
                        len_m1 => to_unsigned(0, config_c.len_width),
                        size_l2 => to_unsigned(bus_l2_c, 3),
                        burst => BURST_INCR,
                        cache => "0110",
                        prot => "101",
                        valid => true);

      when ST_LD_AR =>
        if r.cmd.incr = '1' then
          ar_o <= address(config_c,
                          id => channel_id(r.cmd.channel),
                          addr => r.addr,
                          len_m1 => resize(r.part_m1, config_c.len_width),
                          size_l2 => r.cmd.size_l2,
                          burst => BURST_INCR,
                          cache => r.cmd.cache,
                          prot => r.cmd.prot,
                          valid => true);
        else
          ar_o <= address(config_c,
                          id => channel_id(r.cmd.channel),
                          addr => r.addr,
                          len_m1 => resize(r.part_m1, config_c.len_width),
                          size_l2 => r.cmd.size_l2,
                          burst => BURST_FIXED,
                          cache => r.cmd.cache,
                          prot => r.cmd.prot,
                          valid => true);
        end if;

      when others =>
        null;
    end case;

    r_o <= accept(config_c, r.state = ST_FETCH_R or r.state = ST_LD_R);

    fetch_ready_o <= '0';
    if r.state = ST_IDLE and r.slot.valid = '0' then
      fetch_ready_o <= '1';
    end if;
    fetch_o <= r.rsp;

    load_ready_o <= not r.slot.valid;

    for c in 0 to channel_count_c-1
    loop
      busy_o(c) <= '0';
      if r.slot.valid = '1' and r.slot.channel = to_unsigned(c, channel_t'length) then
        busy_o(c) <= '1';
      end if;
      if r.cmd.channel = to_unsigned(c, channel_t'length) then
        case r.state is
          when ST_LD_PREP | ST_LD_AR | ST_LD_R | ST_LD_NEXT | ST_LD_ACK =>
            busy_o(c) <= '1';
          when others =>
            if r.push_valid = '1' then
              busy_o(c) <= '1';
            end if;
        end case;
      end if;
    end loop;

    error_o <= r.error;
    pushed_o <= r.wptr;
    poisoned_o <= r.poisoned;
    poison_o <= r.poison;
    ack_o <= r.ack;

    word := r.wp(bus_l2_c+word_l2_c-1 downto bus_l2_c);
    for l in 0 to bus_bytes_c-1
    loop
      k := to_unsigned(l, bus_l2_c) - r.wp(bus_l2_c-1 downto 0);
      if l < to_integer(r.wp(bus_l2_c-1 downto 0)) then
        lane_addr := resize(r.cmd.channel & (word + 1), lane_addr'length);
      else
        lane_addr := resize(r.cmd.channel & word, lane_addr'length);
      end if;
      mfifo_address_o(l) <= resize(lane_addr, lane_addr_t'length);
      mfifo_data_o(l) <= r.push_data(to_integer(r.push_lo + k));
      if r.push_valid = '1' and resize(k, max_bus_bytes_l2_c+1) < r.push_n then
        mfifo_enable_o(l) <= '1';
      else
        mfifo_enable_o(l) <= '0';
      end if;
    end loop;
  end process;

end architecture;
