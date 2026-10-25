library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data;
use nsl_amba.axi4_mm.all;
use nsl_amba.axi_m2m_dma.all;
use nsl_amba.dma_request.all;
use nsl_amba.axi_m2m_dma_priv.all;
use nsl_data.bytestream.all;

-- Write side of axi_m2m_microcoded_dma.
--
-- One store at a time, taken from a one-entry slot.  The store waits
-- until its channel's MFIFO holds all its bytes, then issues its
-- burst (two when crossing a 4 kB boundary): address first, data
-- beats once the address is accepted, then waits for the response.
--
-- Data beats go through a pipeline: the MFIFO lane RAMs' read port is
-- the first stage (the RAM holds its output while not read), then a
-- two-entry W queue whose head drives the W channel.  A beat moves
-- from the RAM to the queue when the queue has a free entry, not
-- counting the head WREADY may take this cycle, and the next MFIFO
-- read issues when the beat in the RAM's output moves or there is
-- none: both only depend on registered state, WREADY only pops the
-- queue.  Beats go out one per cycle while WREADY stays high.  Each beat reads the lanes at the
-- channel's read pointer and rotates them to the beat's byte lanes.
--
-- With an endian swap, bytes are permuted within their group of
-- lanes after the rotation: a store's groups are lane-aligned, as the
-- DMA-330 requires DAR to be aligned to the swap size.  A group may
-- span several beats (the swap size is bounded by the larger of the
-- source and destination burst sizes): the MFIFO is read from the
-- start of the beat's group, and the group's bytes are only released
-- once its last beat is read.
--
-- Stores of an aborted channel that did not start are dropped.
entity axi_m2m_dma_writer is
  generic(
    config_c : nsl_amba.axi4_mm.config_t;
    channel_count_c : positive;
    mfifo_depth_l2_c : positive
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    aw_o : out nsl_amba.axi4_mm.address_t;
    aw_i : in nsl_amba.axi4_mm.handshake_t;
    w_o : out nsl_amba.axi4_mm.write_data_t;
    w_i : in nsl_amba.axi4_mm.handshake_t;
    b_o : out nsl_amba.axi4_mm.handshake_t;
    b_i : in nsl_amba.axi4_mm.write_response_t;

    store_i : in transfer_t;
    store_ready_o : out std_ulogic;

    busy_o : out std_ulogic_vector(0 to channel_count_c-1);
    error_o : out std_ulogic_vector(0 to channel_count_c-1);
    abort_i : in std_ulogic_vector(0 to channel_count_c-1);
    clear_i : in std_ulogic_vector(0 to channel_count_c-1);
    pushed_i : in ptr_vector(0 to channel_count_c-1);
    popped_o : out ptr_vector(0 to channel_count_c-1);

    mfifo_address_o : out lane_addr_vector(0 to 2**config_c.data_bus_width_l2-1);
    mfifo_enable_o : out std_ulogic;
    mfifo_data_i : in byte_string(0 to 2**config_c.data_bus_width_l2-1);

    ack_o : out ack_request_t;
    ack_grant_i : in std_ulogic
    );
end entity;

architecture beh of axi_m2m_dma_writer is

  constant bus_l2_c : natural := config_c.data_bus_width_l2;
  constant bus_bytes_c : natural := 2**bus_l2_c;
  constant word_l2_c : natural := mfifo_depth_l2_c;
  constant cap_l2_c : natural := mfifo_depth_l2_c + bus_l2_c;

  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_PREP,
    ST_WAIT,
    ST_AW,
    ST_W,
    ST_B,
    ST_NEXT,
    ST_ACK
    );

  -- A beat whose data is being read from the MFIFO
  type stage_t is
  record
    valid: std_ulogic;
    lo: unsigned(bus_l2_c-1 downto 0);
    n: unsigned(max_bus_bytes_l2_c downto 0);
    rot: unsigned(bus_l2_c-1 downto 0);
    last: std_ulogic;
  end record;

  -- W queue entry
  type beat_t is
  record
    valid: std_ulogic;
    data: byte_string(0 to bus_bytes_c-1);
    strb: std_ulogic_vector(0 to bus_bytes_c-1);
    last: std_ulogic;
  end record;

  type regs_t is
  record
    state: state_t;
    slot: transfer_t;
    cmd: transfer_t;

    -- Read pointer of the current store channel and pointer value
    -- once the store is done.
    rp: ptr_t;
    target: ptr_t;
    -- Start of the swap group holding rp, where MFIFO reads start
    rg: ptr_t;
    rptr: ptr_vector(0 to channel_count_c-1);

    -- Current burst
    addr: unsigned(31 downto 0);
    part_m1: unsigned(3 downto 0);
    split: std_ulogic;
    -- Beats left to read from the MFIFO in current burst
    left: unsigned(4 downto 0);

    -- Span of the next beat
    lo: unsigned(bus_l2_c-1 downto 0);
    n: unsigned(max_bus_bytes_l2_c downto 0);

    s1: stage_t;
    -- W queue: head, driving the W channel, and second entry
    w: beat_t;
    w2: beat_t;

    error: std_ulogic_vector(0 to channel_count_c-1);
    ack: ack_request_t;
  end record;

  signal r, rin: regs_t;

  function channel_id(ch : channel_t) return std_ulogic_vector is
  begin
    return std_ulogic_vector(resize(ch, config_c.id_width));
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

  function pointer(ptrs : ptr_vector; ch : channel_t) return ptr_t is
    variable ret : ptr_t := (others => '0');
  begin
    for c in ptrs'range
    loop
      if ch = to_unsigned(c, ch'length) then
        ret := ptrs(c);
      end if;
    end loop;
    return ret;
  end function;

  -- Byte lanes lo to lo + n - 1
  function strobe(lo : unsigned(bus_l2_c-1 downto 0);
                  n : unsigned(max_bus_bytes_l2_c downto 0)) return std_ulogic_vector
  is
    variable ret : std_ulogic_vector(0 to bus_bytes_c-1);
  begin
    for b in ret'range
    loop
      if resize(to_unsigned(b, bus_l2_c) - lo, n'length) < n then
        ret(b) := '1';
      else
        ret(b) := '0';
      end if;
    end loop;
    return ret;
  end function;

  -- Bus lane b takes MFIFO lane b + rot
  function rotate(lanes : byte_string(0 to bus_bytes_c-1);
                  rot : unsigned(bus_l2_c-1 downto 0)) return byte_string
  is
    variable ret : byte_string(0 to bus_bytes_c-1);
  begin
    for b in ret'range
    loop
      ret(b) := lanes(to_integer(to_unsigned(b, bus_l2_c) + rot));
    end loop;
    return ret;
  end function;

  -- Bus lane b takes lane b xor (2**swap_l2 - 1)
  function swap(lanes : byte_string(0 to bus_bytes_c-1);
                swap_l2 : unsigned(2 downto 0)) return byte_string
  is
    variable ret : byte_string(0 to bus_bytes_c-1);
    variable mask : unsigned(bus_l2_c-1 downto 0);
  begin
    for i in mask'range
    loop
      if i < to_integer(swap_l2) then
        mask(i) := '1';
      else
        mask(i) := '0';
      end if;
    end loop;
    for b in ret'range
    loop
      ret(b) := lanes(to_integer(to_unsigned(b, bus_l2_c) xor mask));
    end loop;
    return ret;
  end function;

  -- The W queue has a free entry, whether or not its head is taken
  function w_room(r : regs_t) return boolean
  is
  begin
    return r.w.valid = '0' or r.w2.valid = '0';
  end function;

  -- Issue a MFIFO read for the next beat on this cycle
  function issue(r : regs_t) return boolean
  is
  begin
    return r.state = ST_W and r.left /= 0 and (r.s1.valid = '0' or w_room(r));
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
      r.s1.valid <= '0';
      r.w.valid <= '0';
      r.w2.valid <= '0';
      r.error <= (others => '0');
      r.ack.valid <= '0';
    end if;
  end process;

  transition: process(r, aw_i, w_i, b_i, store_i, abort_i, clear_i,
                      pushed_i, mfifo_data_i, ack_grant_i) is
    variable page_m1 : unsigned(11 downto 0);
    variable w_accept, s1_move, do_issue : boolean;
    variable beat : beat_t;
    variable avail : ptr_t;
    variable popped : ptr_t;
    variable gmask, end_lo : unsigned(bus_l2_c-1 downto 0);
    -- The beat issued ends its swap group
    variable group_end : boolean;
  begin
    rin <= r;

    rin.error <= (others => '0');

    page_m1 := shift_right(not r.cmd.addr(11 downto 0), to_integer(r.cmd.size_l2));
    w_accept := r.w.valid = '1' and is_ready(config_c, w_i);
    s1_move := r.s1.valid = '1' and w_room(r);
    do_issue := issue(r);
    avail := ptr_wrap(pointer(pushed_i, r.cmd.channel) - r.target, cap_l2_c);
    popped := ptr_wrap(r.rp + r.n, cap_l2_c);
    for i in gmask'range
    loop
      if i < to_integer(r.cmd.swap_l2) then
        gmask(i) := '1';
      else
        gmask(i) := '0';
      end if;
    end loop;
    end_lo := r.lo + resize(r.n, bus_l2_c);
    group_end := r.cmd.incr = '0' or (end_lo and gmask) = 0 or r.left = 1;

    if r.slot.valid = '0' and store_i.valid = '1' then
      rin.slot <= store_i;
    end if;

    beat.valid := '1';
    beat.last := r.s1.last;
    beat.strb := strobe(r.s1.lo, r.s1.n);
    if r.cmd.zero = '1' then
      beat.data := (others => (others => '0'));
    else
      beat.data := swap(rotate(mfifo_data_i, r.s1.rot), r.cmd.swap_l2);
    end if;

    -- A full queue takes no beat, so the second entry is free whenever
    -- one moves in.
    if w_accept then
      if r.w2.valid = '1' then
        rin.w <= r.w2;
        rin.w2.valid <= '0';
      elsif s1_move then
        rin.w <= beat;
      else
        rin.w.valid <= '0';
      end if;
    elsif s1_move then
      if r.w.valid = '1' then
        rin.w2 <= beat;
      else
        rin.w <= beat;
      end if;
    end if;

    if do_issue then
      rin.s1.valid <= '1';
      rin.s1.lo <= r.lo;
      rin.s1.n <= r.n;
      rin.s1.rot <= r.rp(bus_l2_c-1 downto 0) - r.lo;
      if r.left = 1 then
        rin.s1.last <= '1';
      else
        rin.s1.last <= '0';
      end if;
      rin.left <= r.left - 1;
      if r.cmd.incr = '1' then
        rin.lo <= (r.lo and not size_mask(r.cmd.size_l2)(bus_l2_c-1 downto 0))
                  + resize(size_bytes(r.cmd.size_l2), bus_l2_c);
        rin.n <= size_bytes(r.cmd.size_l2);
      end if;
      if r.cmd.zero = '0' then
        rin.rp <= popped;
        if group_end then
          rin.rg <= popped;
          for c in 0 to channel_count_c-1
          loop
            if r.cmd.channel = to_unsigned(c, channel_t'length) then
              rin.rptr(c) <= popped;
            end if;
          end loop;
        end if;
      end if;
    elsif s1_move then
      rin.s1.valid <= '0';
    end if;

    case r.state is
      when ST_RESET =>
        rin.rptr <= (others => (others => '0'));
        rin.state <= ST_IDLE;

      when ST_IDLE =>
        if r.slot.valid = '1' then
          rin.slot.valid <= '0';
          rin.cmd <= r.slot;
          rin.rp <= pointer(r.rptr, r.slot.channel);
          rin.rg <= pointer(r.rptr, r.slot.channel);
          if not is_aborted(abort_i, r.slot.channel) then
            rin.state <= ST_PREP;
          end if;
        end if;

      when ST_PREP =>
        rin.target <= ptr_wrap(r.rp + r.cmd.bytes, cap_l2_c);
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
        if r.cmd.zero = '1' then
          rin.state <= ST_AW;
        else
          rin.state <= ST_WAIT;
        end if;

      when ST_WAIT =>
        if is_aborted(abort_i, r.cmd.channel) then
          rin.state <= ST_IDLE;
        elsif not ptr_negative(avail, cap_l2_c) then
          rin.state <= ST_AW;
        end if;

      when ST_AW =>
        if is_ready(config_c, aw_i) then
          rin.left <= resize(r.part_m1, 5) + 1;
          rin.state <= ST_W;
        end if;

      when ST_W =>
        if w_accept and r.w.last = '1' then
          rin.state <= ST_B;
        end if;

      when ST_B =>
        if is_valid(config_c, b_i) then
          if resp(config_c, b_i) /= RESP_OKAY then
            rin.error(to_integer(r.cmd.channel)) <= '1';
          end if;

          if r.split = '1' then
            rin.state <= ST_NEXT;
          elsif r.cmd.ack = '1' then
            rin.ack.valid <= '1';
            rin.ack.periph <= r.cmd.periph;
            if r.cmd.ack_burst = '1' then
              rin.ack.atype <= datype_burst_c;
            else
              rin.ack.atype <= datype_single_c;
            end if;
            rin.state <= ST_ACK;
          else
            rin.state <= ST_IDLE;
          end if;
        end if;

      when ST_NEXT =>
        rin.addr <= (r.addr(31 downto 12) + 1) & x"000";
        rin.part_m1 <= r.cmd.len_m1 + not r.part_m1;
        rin.split <= '0';
        rin.state <= ST_AW;

      when ST_ACK =>
        if ack_grant_i = '1' then
          rin.ack.valid <= '0';
          rin.state <= ST_IDLE;
        end if;
    end case;

    for c in 0 to channel_count_c-1
    loop
      if clear_i(c) = '1' then
        rin.rptr(c) <= (others => '0');
      end if;
    end loop;
  end process;

  moore: process(r) is
    variable word : unsigned(word_l2_c-1 downto 0);
    variable lane_addr : unsigned(word_l2_c+2 downto 0);
  begin
    aw_o <= address_defaults(config_c);
    if r.state = ST_AW then
      if r.cmd.incr = '1' then
        aw_o <= address(config_c,
                        id => channel_id(r.cmd.channel),
                        addr => r.addr,
                        len_m1 => resize(r.part_m1, config_c.len_width),
                        size_l2 => r.cmd.size_l2,
                        burst => BURST_INCR,
                        cache => r.cmd.cache,
                        prot => r.cmd.prot,
                        valid => true);
      else
        aw_o <= address(config_c,
                        id => channel_id(r.cmd.channel),
                        addr => r.addr,
                        len_m1 => resize(r.part_m1, config_c.len_width),
                        size_l2 => r.cmd.size_l2,
                        burst => BURST_FIXED,
                        cache => r.cmd.cache,
                        prot => r.cmd.prot,
                        valid => true);
      end if;
    end if;

    w_o <= write_data(config_c,
                      bytes => r.w.data,
                      strb => r.w.strb,
                      last => r.w.last = '1',
                      valid => r.w.valid = '1');

    b_o <= accept(config_c, r.state = ST_B);

    store_ready_o <= not r.slot.valid;

    for c in 0 to channel_count_c-1
    loop
      busy_o(c) <= '0';
      if r.slot.valid = '1' and r.slot.channel = to_unsigned(c, channel_t'length) then
        busy_o(c) <= '1';
      end if;
      if r.state /= ST_IDLE and r.state /= ST_RESET
        and r.cmd.channel = to_unsigned(c, channel_t'length) then
        busy_o(c) <= '1';
      end if;
    end loop;

    error_o <= r.error;
    popped_o <= r.rptr;
    ack_o <= r.ack;

    word := r.rg(bus_l2_c+word_l2_c-1 downto bus_l2_c);
    if issue(r) then
      mfifo_enable_o <= '1';
    else
      mfifo_enable_o <= '0';
    end if;

    for l in 0 to bus_bytes_c-1
    loop
      if l < to_integer(r.rg(bus_l2_c-1 downto 0)) then
        lane_addr := resize(r.cmd.channel & (word + 1), lane_addr'length);
      else
        lane_addr := resize(r.cmd.channel & word, lane_addr'length);
      end if;
      mfifo_address_o(l) <= resize(lane_addr, lane_addr_t'length);
    end loop;
  end process;

end architecture;
