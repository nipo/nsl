library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_simulation;
use nsl_amba.axi4_mm.all;
use nsl_amba.axi_m2m_dma.all;
use nsl_amba.dma_request.all;
use nsl_data.bytestream.all;
use nsl_data.text.all;
use nsl_simulation.logging.all;

library work;
use work.dma_vector.all;

-- One microcoded DMA instance, its memory and peripheral models,
-- following a script its reference model generated (see dma_vector).
--
-- A main process interprets the script: memory accesses, DMA resets,
-- register accesses through the DMA's APB slave (debug instructions,
-- interrupt controls, waits for register values), peripheral scripts.
-- The DMA is held in reset until the script releases it.
-- Monitors match what the DMA does against the script's expectations:
-- data reads and data writes per channel in order, acknowledges per
-- peripheral in order, and their ordering constraints.  Instruction
-- fetches, reads with AxPROT 0b101 and AxCACHE 0b0110 (the script's
-- data reads never have both), are not data transfers.
entity dma_harness is
  generic(
    channel_count_c : positive;
    bus_width_c : positive;
    endian_swap_c : boolean;
    boot_from_pc_c : boolean;
    boot_addr_c : unsigned(31 downto 0);
    request_depth_c : positive;
    failed_store_fault_c : boolean;
    name_c : string;
    script_c : word_vector
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;
    done_o : out std_ulogic
    );
end entity;

architecture beh of dma_harness is

  constant dma_config_c : config_t := config(address_width => 32,
                                             data_bus_width => bus_width_c,
                                             id_width => 3,
                                             max_length => 16,
                                             size => true,
                                             burst => true,
                                             cache => true);
  constant ram_config_c : config_t := config(address_width => 32,
                                             data_bus_width => bus_width_c,
                                             id_width => 4,
                                             max_length => 16,
                                             size => true,
                                             burst => true,
                                             cache => true);
  constant routing_table_c : nsl_amba.address.address_vector
    := nsl_amba.address.routing_table(32, "x0000----/16");

  constant bus_bytes_c : natural := bus_width_c / 8;
  constant bus_l2_c : natural := dma_config_c.data_bus_width_l2;
  constant event_count_c : natural := 8;
  constant peripheral_count_c : natural := 2;
  constant mfifo_depth_l2_c : natural := 4;
  constant timeout_c : natural := 200000;
  constant apb_config_c : nsl_amba.apb.config_t := nsl_amba.apb.apb3_config(address_width => 12,
                                                                            data_bus_width => 32);

  signal master_bus : bus_vector(0 to 1);
  -- The DMA's port on the crossbar side of the throttle
  signal dma_xbar_m : master_t;
  signal dma_xbar_s : slave_t;
  -- Throttle stages and their pseudo-random acceptance
  signal w_stage_s : write_data_t;
  signal r_stage_s : read_data_t;
  signal lfsr_s : std_ulogic_vector(15 downto 0);
  signal slave_bus : bus_vector(0 to 0);

  signal apb_m_s : nsl_amba.apb.master_t;
  signal apb_s_s : nsl_amba.apb.slave_t;
  signal dma_reset_n_s, dma_hold_n_s : std_ulogic;
  -- Clock cycles since reset
  signal cycle_s : natural := 0;

  signal irq_s : std_ulogic_vector(event_count_c-1 downto 0);
  signal irq_abort_s : std_ulogic;
  signal periph_s : peripheral_vector(0 to peripheral_count_c-1);
  signal dmac_s : dmac_vector(0 to peripheral_count_c-1);

  -- Main to monitors and peripheral models
  signal ignore_s : std_ulogic_vector(0 to channel_count_c-1);
  -- Script index of each peripheral's current operation, if any
  type int_vector is array (natural range <>) of integer;
  signal periph_start_s : int_vector(0 to peripheral_count_c-1);

  -- Monitors to main: transfers and acknowledges matched so far
  signal read_count_s, write_count_s : natural_vector(0 to channel_count_c-1);
  signal ack_count_s : natural_vector(0 to peripheral_count_c-1);
  -- Requests the DMA took since the peripheral's script started
  signal taken_s : natural_vector(0 to peripheral_count_c-1);

  -- Bytes a beat moves: lanes lo to the end of its size-aligned
  -- container.
  function beat_lanes(addr : unsigned; size_l2 : natural) return std_ulogic_vector
  is
    variable ret : std_ulogic_vector(0 to bus_bytes_c-1) := (others => '0');
    constant lo : natural := to_integer(addr(bus_l2_c-1 downto 0));
    constant hi : natural := lo - (lo mod 2**size_l2) + 2**size_l2;
  begin
    for l in lo to hi - 1
    loop
      ret(l) := '1';
    end loop;
    return ret;
  end function;

  function next_beat(addr : unsigned(31 downto 0); size_l2 : natural; incr : boolean) return unsigned
  is
  begin
    if not incr then
      return addr;
    end if;
    return (addr and not to_unsigned(2**size_l2 - 1, 32)) + 2**size_l2;
  end function;

  function resp_code(r : resp_enum_t) return natural is
  begin
    case r is
      when RESP_OKAY => return 0;
      when RESP_EXOKAY => return 1;
      when RESP_SLVERR => return 2;
      when RESP_DECERR => return 3;
    end case;
  end function;

  function hex(v : unsigned) return string is
  begin
    return to_hex_string(std_ulogic_vector(v));
  end function;

  -- Received burst, compared with the expectation at index x of the
  -- script.
  procedure check_burst(what : string;
                        x : natural;
                        addr : unsigned(31 downto 0);
                        beats, size_l2 : natural;
                        incr : boolean;
                        cache, prot : std_ulogic_vector;
                        resp : natural;
                        data : byte_string) is
    constant s : word_vector := script_c;
    -- Bit 30 of the byte count: the data is unknown (a failed load
    -- brought it), only its length is checked
    constant exp_bytes : natural := to_integer(s(x + xfer_bytes_c)(29 downto 0));
    constant known : boolean := s(x + xfer_bytes_c)(30) = '0';
    variable incr_n : natural := 0;
  begin
    if incr then
      incr_n := 1;
    end if;
    assert s(x + xfer_addr_c) = addr
      and nat(s(x + xfer_beats_c)) = beats
      and nat(s(x + xfer_size_c)) = size_l2
      and nat(s(x + xfer_incr_c)) = incr_n
      and s(x + xfer_cache_c)(3 downto 0) = unsigned(cache)
      and s(x + xfer_prot_c)(2 downto 0) = unsigned(prot)
      and nat(s(x + xfer_resp_c)) = resp
      report name_c & ": " & what & " of channel " & integer'image(nat(s(x + xfer_channel_c)))
      & ": got 0x" & hex(addr) & " beats " & integer'image(beats)
      & " size_l2 " & integer'image(size_l2) & " incr " & integer'image(incr_n)
      & " cache " & to_string(cache) & " prot " & to_string(prot)
      & " resp " & integer'image(resp)
      & ", expected 0x" & hex(s(x + xfer_addr_c))
      & " beats " & integer'image(nat(s(x + xfer_beats_c)))
      & " size_l2 " & integer'image(nat(s(x + xfer_size_c)))
      & " incr " & integer'image(nat(s(x + xfer_incr_c)))
      & " cache " & integer'image(nat(s(x + xfer_cache_c)))
      & " prot " & integer'image(nat(s(x + xfer_prot_c)))
      & " resp " & integer'image(nat(s(x + xfer_resp_c)))
      severity failure;
    assert data'length = exp_bytes
      and (not known or data = bytes_at(s, x + xfer_data_c, exp_bytes))
      report name_c & ": " & what & " of channel " & integer'image(nat(s(x + xfer_channel_c)))
      & " at 0x" & hex(addr) & ": data " & to_string(data)
      & ", expected " & to_string(bytes_at(s, x + xfer_data_c, exp_bytes))
      severity failure;
  end procedure;

begin

  dma_reset_n_s <= reset_n_i and dma_hold_n_s;

  dut: nsl_amba.axi_m2m_dma.axi_m2m_microcoded_dma
    generic map(
      config_c => dma_config_c,
      apb_config_c => apb_config_c,
      channel_count_c => channel_count_c,
      event_count_c => event_count_c,
      peripheral_count_c => peripheral_count_c,
      request_depth_c => request_depth_c,
      failed_store_fault_c => failed_store_fault_c,
      mfifo_depth_l2_c => mfifo_depth_l2_c,
      endian_swap_c => endian_swap_c,
      boot_from_pc_c => boot_from_pc_c,
      boot_addr_c => boot_addr_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => dma_reset_n_s,

      axi_o => master_bus(1).m,
      axi_i => master_bus(1).s,

      apb_i => apb_m_s,
      apb_o => apb_s_s,

      irq_o => irq_s,
      irq_abort_o => irq_abort_s,

      periph_i => periph_s,
      periph_o => dmac_s
      );

  xbar: nsl_amba.mm_routing.axi4_mm_crossbar
    generic map(
      master_config_c => dma_config_c,
      slave_config_c => ram_config_c,
      master_count_c => 2,
      routing_table_c => routing_table_c,
      default_slave_c => -1
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      slave_i(0) => master_bus(0).m,
      slave_i(1) => dma_xbar_m,
      slave_o(0) => master_bus(0).s,
      slave_o(1) => dma_xbar_s,
      master_o(0) => slave_bus(0).m,
      master_i(0) => slave_bus(0).s
      );

  ram: nsl_amba.ram.axi4_mm_full_ram
    generic map(
      config_c => ram_config_c,
      byte_size_l2_c => 16
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      axi_i => slave_bus(0).m,
      axi_o => slave_bus(0).s
      );

  -- Pseudo-random backpressure on the DMA's W and R channels: a stage
  -- on each takes a beat when empty and its LFSR bit is set.
  throttle_regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      lfsr_s <= lfsr_s(14 downto 0)
                & (lfsr_s(15) xor lfsr_s(13) xor lfsr_s(12) xor lfsr_s(10));
      if w_stage_s.valid = '1' and dma_xbar_s.w.ready = '1' then
        w_stage_s.valid <= '0';
      end if;
      if master_bus(1).m.w.valid = '1' and w_stage_s.valid = '0' and lfsr_s(0) = '1' then
        w_stage_s <= master_bus(1).m.w;
      end if;
      if r_stage_s.valid = '1' and master_bus(1).m.r.ready = '1' then
        r_stage_s.valid <= '0';
      end if;
      if dma_xbar_s.r.valid = '1' and r_stage_s.valid = '0' and lfsr_s(1) = '1' then
        r_stage_s <= dma_xbar_s.r;
      end if;
    end if;
    if reset_n_i = '0' then
      lfsr_s <= x"ace1";
      w_stage_s.valid <= '0';
      r_stage_s.valid <= '0';
    end if;
  end process;

  throttle: process(master_bus(1).m, dma_xbar_s, w_stage_s, r_stage_s, lfsr_s) is
  begin
    dma_xbar_m <= master_bus(1).m;
    dma_xbar_m.w <= w_stage_s;
    dma_xbar_m.r.ready <= not r_stage_s.valid and lfsr_s(1);
    master_bus(1).s <= dma_xbar_s;
    master_bus(1).s.w.ready <= not w_stage_s.valid and lfsr_s(0);
    master_bus(1).s.r <= r_stage_s;
  end process;

  cycles: process(clock_i) is
  begin
    if rising_edge(clock_i) then
      cycle_s <= cycle_s + 1;
    end if;
  end process;

  -- Data reads of the DMA: one burst at a time.
  read_monitor: process is
    constant s : word_vector := script_c;
    variable cursor, issued, done : natural_vector(0 to channel_count_c-1) := (others => 0);
    variable active, fetch, ignored : boolean := false;
    variable ch, x, beats, size_l2, resp, len : natural;
    variable addr, beat_addr : unsigned(31 downto 0);
    variable incr : boolean;
    variable cache : cache_t;
    variable prot : prot_t;
    variable data : byte_string(0 to 255);
    variable lanes : std_ulogic_vector(0 to bus_bytes_c-1);
    variable beat : byte_string(0 to bus_bytes_c-1);
  begin
    read_count_s <= (others => 0);
    loop
      wait until rising_edge(clock_i);

      if is_valid(dma_config_c, master_bus(1).s.r) and is_ready(dma_config_c, master_bus(1).m.r) then
        assert active
          report name_c & ": read data without a burst"
          severity failure;
        if not fetch and not ignored then
          lanes := beat_lanes(beat_addr, size_l2);
          beat := bytes(dma_config_c, master_bus(1).s.r);
          for l in lanes'range
          loop
            if lanes(l) = '1' then
              data(len) := beat(l);
              len := len + 1;
            end if;
          end loop;
          if resp = 0 then
            resp := resp_code(nsl_amba.axi4_mm.resp(dma_config_c, master_bus(1).s.r));
          end if;
          beat_addr := next_beat(beat_addr, size_l2, incr);
        end if;
        if is_last(dma_config_c, master_bus(1).s.r) then
          active := false;
          if not fetch and not ignored then
            x := find(s, cursor(ch), op_expect_read_c, ch);
            if resp /= 0 then
              len := 0;
            end if;
            check_burst("read", x, addr, beats, size_l2, incr, cache, prot, resp, data(0 to len-1));
            cursor(ch) := x + op_length(s(x));
            done(ch) := done(ch) + 1;
            read_count_s <= done;
          end if;
        end if;
      end if;

      if is_valid(dma_config_c, master_bus(1).m.ar) and is_ready(dma_config_c, master_bus(1).s.ar) then
        assert not active
          report name_c & ": overlapping read bursts"
          severity failure;
        active := true;
        prot := nsl_amba.axi4_mm.prot(dma_config_c, master_bus(1).m.ar);
        cache := nsl_amba.axi4_mm.cache(dma_config_c, master_bus(1).m.ar);
        fetch := prot = "101" and cache = "0110";
        ch := 0;
        ignored := false;
        if not fetch then
          ch := to_integer(unsigned(id(dma_config_c, master_bus(1).m.ar)));
          ignored := ignore_s(ch) = '1';
        end if;
        addr := address(dma_config_c, master_bus(1).m.ar);
        beat_addr := addr;
        beats := to_integer(length_m1(dma_config_c, master_bus(1).m.ar, 8)) + 1;
        size_l2 := to_integer(nsl_amba.axi4_mm.size_l2(dma_config_c, master_bus(1).m.ar));
        incr := burst(dma_config_c, master_bus(1).m.ar) = BURST_INCR;
        resp := 0;
        len := 0;
        if not fetch and not ignored then
          x := find(s, cursor(ch), op_expect_read_c, ch);
          assert x <= s'high
            report name_c & ": unexpected read of channel " & integer'image(ch)
            & " at 0x" & hex(addr)
            severity failure;
          if nat(s(x + xfer_after_channel_c)) /= no_channel_c then
            assert issued(nat(s(x + xfer_after_channel_c))) >= nat(s(x + xfer_after_count_c))
              report name_c & ": read of channel " & integer'image(ch)
              & " at 0x" & hex(addr) & " issued before the "
              & integer'image(nat(s(x + xfer_after_count_c))) & " reads of channel "
              & integer'image(nat(s(x + xfer_after_channel_c))) & " preceding its event"
              severity failure;
          end if;
          issued(ch) := issued(ch) + 1;
        end if;
      end if;
    end loop;
  end process;

  -- Data writes of the DMA: one burst at a time.
  write_monitor: process is
    constant s : word_vector := script_c;
    variable cursor, issued, done : natural_vector(0 to channel_count_c-1) := (others => 0);
    variable active, ignored : boolean := false;
    variable ch, x, beats, size_l2, len : natural;
    variable addr, beat_addr : unsigned(31 downto 0);
    variable incr : boolean;
    variable cache : cache_t;
    variable prot : prot_t;
    variable data : byte_string(0 to 255);
    variable lanes, strobe : std_ulogic_vector(0 to bus_bytes_c-1);
    variable beat : byte_string(0 to bus_bytes_c-1);
  begin
    write_count_s <= (others => 0);
    loop
      wait until rising_edge(clock_i);

      if is_valid(dma_config_c, master_bus(1).s.b) and is_ready(dma_config_c, master_bus(1).m.b) then
        assert active
          report name_c & ": write response without a burst"
          severity failure;
        active := false;
        if not ignored then
          x := find(s, cursor(ch), op_expect_write_c, ch);
          check_burst("write", x, addr, beats, size_l2, incr, cache, prot,
                      resp_code(nsl_amba.axi4_mm.resp(dma_config_c, master_bus(1).s.b)),
                      data(0 to len-1));
          cursor(ch) := x + op_length(s(x));
          done(ch) := done(ch) + 1;
          write_count_s <= done;
        end if;
      end if;

      if is_valid(dma_config_c, master_bus(1).m.w) and is_ready(dma_config_c, master_bus(1).s.w) then
        assert active
          report name_c & ": write data without a burst"
          severity failure;
        if not ignored then
          lanes := beat_lanes(beat_addr, size_l2);
          strobe := strb(dma_config_c, master_bus(1).m.w);
          beat := bytes(dma_config_c, master_bus(1).m.w);
          assert strobe = lanes
            report name_c & ": write of channel " & integer'image(ch)
            & " beat at 0x" & hex(beat_addr) & ": strobe " & to_string(strobe)
            & ", expected " & to_string(lanes)
            severity failure;
          for l in lanes'range
          loop
            if lanes(l) = '1' then
              data(len) := beat(l);
              len := len + 1;
            end if;
          end loop;
          beat_addr := next_beat(beat_addr, size_l2, incr);
        end if;
      end if;

      if is_valid(dma_config_c, master_bus(1).m.aw) and is_ready(dma_config_c, master_bus(1).s.aw) then
        assert not active
          report name_c & ": overlapping write bursts"
          severity failure;
        active := true;
        ch := to_integer(unsigned(id(dma_config_c, master_bus(1).m.aw)));
        ignored := ignore_s(ch) = '1';
        addr := address(dma_config_c, master_bus(1).m.aw);
        beat_addr := addr;
        beats := to_integer(length_m1(dma_config_c, master_bus(1).m.aw, 8)) + 1;
        size_l2 := to_integer(nsl_amba.axi4_mm.size_l2(dma_config_c, master_bus(1).m.aw));
        incr := burst(dma_config_c, master_bus(1).m.aw) = BURST_INCR;
        cache := nsl_amba.axi4_mm.cache(dma_config_c, master_bus(1).m.aw);
        prot := nsl_amba.axi4_mm.prot(dma_config_c, master_bus(1).m.aw);
        len := 0;
        if not ignored then
          x := find(s, cursor(ch), op_expect_write_c, ch);
          assert x <= s'high
            report name_c & ": unexpected write of channel " & integer'image(ch)
            & " at 0x" & hex(addr)
            severity failure;
          if nat(s(x + xfer_after_channel_c)) /= no_channel_c then
            assert issued(nat(s(x + xfer_after_channel_c))) >= nat(s(x + xfer_after_count_c))
              report name_c & ": write of channel " & integer'image(ch)
              & " at 0x" & hex(addr) & " issued before the "
              & integer'image(nat(s(x + xfer_after_count_c))) & " writes of channel "
              & integer'image(nat(s(x + xfer_after_channel_c))) & " preceding its event"
              severity failure;
          end if;
          issued(ch) := issued(ch) + 1;
        end if;
      end if;
    end loop;
  end process;

  -- Scripted peripherals: present their requests one at a time, with
  -- at most the script's count of them not acknowledged; answer a
  -- flush acknowledge with a flush request and present again the
  -- requests it dropped.
  -- Acknowledges are matched against the script.
  peripherals: for p in 0 to peripheral_count_c-1
  generate
    model: process is
      constant s : word_vector := script_c;
      variable start : integer := -1;
      variable count, idx, unacked, cursor, acks, x, ch, outstanding, taken : natural := 0;
      variable driving, flush_pending, flushing : boolean := false;
      variable atype : natural;
      variable req : word_t;
    begin
      periph_s(p) <= peripheral_idle_c;
      ack_count_s(p) <= 0;
      taken_s(p) <= 0;

      loop
        wait until rising_edge(clock_i);

        if periph_start_s(p) /= start then
          start := periph_start_s(p);
          outstanding := nat(s(start + 2));
          count := nat(s(start + 3));
          taken := 0;
          taken_s(p) <= 0;
          idx := 0;
          unacked := 0;
        end if;

        if dmac_s(p).davalid = '1' then
          if dmac_s(p).datype = datype_single_c then
            atype := 0;
          elsif dmac_s(p).datype = datype_burst_c then
            atype := 1;
          else
            atype := 2;
          end if;
          x := find(s, cursor, op_expect_ack_c, p);
          assert x <= s'high
            report name_c & ": unexpected acknowledge to peripheral " & integer'image(p)
            severity failure;
          assert nat(s(x + ack_type_c)) = atype
            report name_c & ": acknowledge " & integer'image(acks) & " to peripheral "
            & integer'image(p) & " of type " & integer'image(atype)
            & ", expected " & integer'image(nat(s(x + ack_type_c)))
            severity failure;
          ch := nat(s(x + ack_channel_c));
          if ch /= no_channel_c then
            assert read_count_s(ch) >= nat(s(x + ack_reads_c))
              and write_count_s(ch) >= nat(s(x + ack_writes_c))
              report name_c & ": acknowledge " & integer'image(acks) & " to peripheral "
              & integer'image(p) & " before its transfer completed"
              severity failure;
          end if;
          cursor := x + op_length(s(x));
          acks := acks + 1;
          ack_count_s(p) <= acks;

          if atype = 2 then
            flush_pending := true;
            idx := idx - unacked;
            unacked := 0;
          else
            assert unacked > 0
              report name_c & ": acknowledge without a request to peripheral " & integer'image(p)
              severity failure;
            unacked := unacked - 1;
          end if;
        end if;

        if driving and dmac_s(p).drready = '1' then
          driving := false;
          if not flushing then
            taken := taken + 1;
            taken_s(p) <= taken;
          end if;
        end if;

        wait until falling_edge(clock_i);

        if not driving then
          periph_s(p).drvalid <= '0';
          if flush_pending then
            periph_s(p).drvalid <= '1';
            periph_s(p).drtype <= drtype_flush_c;
            periph_s(p).drlast <= '0';
            driving := true;
            flushing := true;
            flush_pending := false;
          elsif start >= 0 and unacked < outstanding and idx < count then
            req := s(start + 4 + idx);
            periph_s(p).drvalid <= '1';
            if req(1 downto 0) = "01" then
              periph_s(p).drtype <= drtype_burst_c;
            else
              periph_s(p).drtype <= drtype_single_c;
            end if;
            periph_s(p).drlast <= req(2);
            driving := true;
            flushing := false;
            idx := idx + 1;
            unacked := unacked + 1;
          end if;
        end if;
      end loop;
    end process;
  end generate;

  main: process is
    constant s : word_vector := script_c;
    variable i, op, n, ch, cycles, count : natural;
    variable rsp : resp_enum_t;
    variable exp_reads, exp_writes : natural_vector(0 to channel_count_c-1) := (others => 0);
    variable exp_acks : natural_vector(0 to peripheral_count_c-1) := (others => 0);
    variable context : natural := 0;
    variable v : word_t;
    variable matched : boolean;
    variable start_cycle : natural;

    procedure mem_write(addr : unsigned(31 downto 0); data : byte_string) is
      alias d : byte_string(0 to data'length-1) is data;
      variable a, i, chunk : natural;
    begin
      a := to_integer(addr);
      i := 0;
      while i < d'length
      loop
        chunk := 32 - (a mod 32);
        if chunk > d'length - i then
          chunk := d'length - i;
        end if;
        burst_write(dma_config_c, clock_i, master_bus(0).s, master_bus(0).m,
                    to_unsigned(a, 32), d(i to i + chunk - 1), rsp);
        assert rsp = RESP_OKAY
          report name_c & ": memory write failed"
          severity failure;
        a := a + chunk;
        i := i + chunk;
      end loop;
    end procedure;

    procedure mem_fill(addr : unsigned(31 downto 0); count : natural; value : byte) is
      constant data : byte_string(0 to count-1) := (others => value);
    begin
      mem_write(addr, data);
    end procedure;

    procedure mem_check(addr : unsigned(31 downto 0); data : byte_string) is
      alias d : byte_string(0 to data'length-1) is data;
      variable rdata : byte_string(0 to 31);
      variable a, i, chunk : natural;
    begin
      a := to_integer(addr);
      i := 0;
      while i < d'length
      loop
        chunk := 32 - (a mod 32);
        if chunk > d'length - i then
          chunk := d'length - i;
        end if;
        burst_read(dma_config_c, clock_i, master_bus(0).s, master_bus(0).m,
                   to_unsigned(a, 32), rdata(0 to chunk-1), rsp);
        assert rsp = RESP_OKAY
          report name_c & ": memory read failed"
          severity failure;
        assert rdata(0 to chunk-1) = d(i to i + chunk - 1)
          report name_c & ": memory at 0x" & hex(to_unsigned(a, 32))
          & ", read " & to_string(rdata(0 to chunk-1))
          & ", expected " & to_string(d(i to i + chunk - 1))
          severity failure;
        a := a + chunk;
        i := i + chunk;
      end loop;
    end procedure;

    -- APB accesses start on a falling edge
    procedure reg_read(offset : natural; value : out word_t) is
      variable err : boolean;
    begin
      if clock_i = '1' then
        wait until falling_edge(clock_i);
      end if;
      nsl_amba.apb.apb_read(apb_config_c, clock_i, apb_s_s, apb_m_s,
                            to_unsigned(offset, 12), value, err);
      assert not err
        report name_c & ": APB read error at 0x" & hex(to_unsigned(offset, 12))
        severity failure;
    end procedure;

    procedure reg_write(offset : natural; value : word_t) is
      variable err : boolean;
    begin
      if clock_i = '1' then
        wait until falling_edge(clock_i);
      end if;
      nsl_amba.apb.apb_write(apb_config_c, clock_i, apb_s_s, apb_m_s,
                             to_unsigned(offset, 12), value, err => err);
      assert not err
        report name_c & ": APB write error at 0x" & hex(to_unsigned(offset, 12))
        severity failure;
    end procedure;

    impure function scenario return string is
    begin
      return text_at(s, context + 2, nat(s(context + 1)));
    end function;

    procedure debug_idle is
      variable v : word_t;
      variable start_cycle : natural;
    begin
      start_cycle := cycle_s;
      loop
        reg_read(reg_dbgstatus_c, v);
        exit when v(0) = '0';
        assert cycle_s - start_cycle < timeout_c
          report name_c & ": " & scenario & ": debug interface stays busy"
          severity failure;
      end loop;
    end procedure;

    function counts_reached(reads, writes, acks, rc, wc, ac : natural_vector) return boolean is
    begin
      for c in reads'range
      loop
        if rc(c) /= reads(c) or wc(c) /= writes(c) then
          return false;
        end if;
      end loop;
      for p in acks'range
      loop
        if ac(p) /= acks(p) then
          return false;
        end if;
      end loop;
      return true;
    end function;

  begin
    done_o <= '0';
    dma_hold_n_s <= '0';
    apb_m_s <= nsl_amba.apb.transfer_idle(apb_config_c);
    ignore_s <= (others => '0');
    periph_start_s <= (others => -1);
    master_bus(0).m.ar <= address_defaults(dma_config_c);
    master_bus(0).m.r <= handshake_defaults(dma_config_c);
    master_bus(0).m.aw <= address_defaults(dma_config_c);
    master_bus(0).m.w <= write_data_defaults(dma_config_c);
    master_bus(0).m.b <= accept(dma_config_c, true);

    wait until reset_n_i = '1';
    wait until falling_edge(clock_i);

    i := 0;
    loop
      op := opcode(s(i));
      n := op_length(s(i));
      exit when op = op_end_c;

      case op is
        when op_log_c =>
          context := i;
          log_info(name_c & ": " & scenario);

        when op_mem_write_c =>
          mem_write(s(i + 1), bytes_at(s, i + 3, nat(s(i + 2))));

        when op_mem_fill_c =>
          mem_fill(s(i + 1), nat(s(i + 2)), std_ulogic_vector(s(i + 3)(7 downto 0)));

        when op_mem_check_c =>
          mem_check(s(i + 1), bytes_at(s, i + 3, nat(s(i + 2))));

        when op_reset_c =>
          wait until falling_edge(clock_i);
          dma_hold_n_s <= '0';
          for k in 1 to 4
          loop
            wait until falling_edge(clock_i);
          end loop;
          dma_hold_n_s <= '1';

        when op_debug_c =>
          debug_idle;
          reg_write(reg_dbginst0_c, s(i + 1));
          reg_write(reg_dbginst1_c, s(i + 2));
          reg_write(reg_dbgcmd_c, to_unsigned(0, 32));
          debug_idle;

        when op_apb_write_c =>
          reg_write(nat(s(i + 1)), s(i + 2));

        when op_apb_check_c =>
          reg_read(nat(s(i + 1)), v);
          assert (v and s(i + 2)) = s(i + 3)
            report name_c & ": " & scenario & ": register 0x" & hex(s(i + 1)(11 downto 0))
            & " reads 0x" & hex(v) & ", expected 0x" & hex(s(i + 3))
            & " under mask 0x" & hex(s(i + 2))
            severity failure;

        when op_wait_regs_c =>
          count := nat(s(i + 1));
          start_cycle := cycle_s;
          loop
            matched := true;
            for k in 0 to count-1
            loop
              reg_read(nat(s(i + 2 + 3 * k)), v);
              if (v and s(i + 3 + 3 * k)) /= s(i + 4 + 3 * k) then
                matched := false;
                if cycle_s - start_cycle >= timeout_c then
                  log_info(name_c & ": register 0x" & hex(s(i + 2 + 3 * k)(11 downto 0))
                           & " reads 0x" & hex(v) & ", expected 0x" & hex(s(i + 4 + 3 * k))
                           & " under mask 0x" & hex(s(i + 3 + 3 * k)));
                end if;
              end if;
            end loop;
            exit when matched;
            assert cycle_s - start_cycle < timeout_c
              report name_c & ": " & scenario & ": registers do not reach their expected values"
              severity failure;
          end loop;

        when op_delay_c =>
          for k in 1 to nat(s(i + 1))
          loop
            wait until rising_edge(clock_i);
          end loop;

        when op_check_irq_c =>
          wait until rising_edge(clock_i);
          assert irq_s = std_ulogic_vector(s(i + 1)(event_count_c-1 downto 0))
            and irq_abort_s = s(i + 2)(0)
            report name_c & ": " & scenario
            & ": irq " & to_string(irq_s) & " abort " & to_string(irq_abort_s)
            & ", expected irq 0x" & hex(s(i + 1)) & " abort " & integer'image(nat(s(i + 2)))
            severity failure;

        when op_periph_c =>
          periph_start_s(nat(s(i + 1))) <= i;

        when op_sync_c =>
          cycles := 0;
          loop
            wait until rising_edge(clock_i);
            exit when counts_reached(exp_reads, exp_writes, exp_acks,
                                     read_count_s, write_count_s, ack_count_s);
            cycles := cycles + 1;
            if cycles >= timeout_c then
              for c in 0 to channel_count_c-1
              loop
                log_info(name_c & ": channel " & integer'image(c)
                         & " reads " & integer'image(read_count_s(c)) & "/" & integer'image(exp_reads(c))
                         & " writes " & integer'image(write_count_s(c)) & "/" & integer'image(exp_writes(c)));
              end loop;
              for p in 0 to peripheral_count_c-1
              loop
                log_info(name_c & ": peripheral " & integer'image(p)
                         & " acknowledges " & integer'image(ack_count_s(p)) & "/" & integer'image(exp_acks(p)));
              end loop;
            end if;
            assert cycles < timeout_c
              report name_c & ": " & scenario
              & ": expected transfers or acknowledges missing"
              severity failure;
          end loop;

        when op_ignore_c =>
          wait until falling_edge(clock_i);
          ignore_s(nat(s(i + 1))) <= s(i + 2)(0);

        when op_check_taken_c =>
          wait until rising_edge(clock_i);
          assert taken_s(nat(s(i + 1))) = nat(s(i + 2))
            report name_c & ": " & scenario & ": peripheral "
            & integer'image(nat(s(i + 1))) & " had "
            & integer'image(taken_s(nat(s(i + 1)))) & " requests taken, expected "
            & integer'image(nat(s(i + 2)))
            severity failure;

        when op_check_busy_c =>
          reg_read(reg_csr0_c + 8 * nat(s(i + 1)), v);
          assert v(3 downto 0) /= 0
            report name_c & ": " & scenario & ": channel "
            & integer'image(nat(s(i + 1))) & " ended too early"
            severity failure;

        when op_expect_read_c =>
          ch := nat(s(i + xfer_channel_c));
          exp_reads(ch) := exp_reads(ch) + 1;

        when op_expect_write_c =>
          ch := nat(s(i + xfer_channel_c));
          exp_writes(ch) := exp_writes(ch) + 1;

        when op_expect_ack_c =>
          exp_acks(nat(s(i + ack_periph_c))) := exp_acks(nat(s(i + ack_periph_c))) + 1;

        when others =>
          assert false
            report name_c & ": unknown script operation " & integer'image(op)
            severity failure;
      end case;

      i := i + n;
    end loop;

    log_info(name_c & ": done");
    done_o <= '1';
    wait;
  end process;

end architecture;
