library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library nsl_qspi, nsl_amba, nsl_bnoc, nsl_data, nsl_simulation;
use nsl_qspi.xip.all;
use nsl_amba.axi4_mm.all;
use nsl_bnoc.framed.all;
use nsl_data.bytestream.all;
use work.qspi_test_support.all;

entity tb is
end entity;

architecture test of tb is
  constant axi_config_c: config_t := config(
    address_width => 32, data_bus_width => 32, id_width => 4,
    max_length => 16, size => true, burst => true, lock => true);
  signal clock_s: std_ulogic := '0';
  signal reset_n_s: std_ulogic := '0';
  signal done_s: boolean := false;
  signal config_s: xip_config_t := xip_config_reset_c;
  signal axi_s: bus_t;
  signal command_s, response_s: framed_bus;
  signal pins_s: nsl_qspi.qspi.qspi_master_o;
  signal pin_input_s: nsl_qspi.qspi.qspi_master_i;
  signal dq_s, enable_s: std_ulogic_vector(3 downto 0);
  signal opcode_s: byte := x"03";
  signal flash_address_s: unsigned(31 downto 0) := (others => '0');
  signal address_bytes_s: positive := 3;
  signal address_lanes_s, data_lanes_s: positive := 1;
  signal dummy_s: natural := 0;
  signal data_bytes_s: positive := 4;
  signal half_period_s: time := 10 ns;
  signal completed_s: natural;
begin
  clock_s <= not clock_s after 5 ns when not done_s else '0';
  lanes: for i in 0 to 3 generate
    dq_s(i) <= pins_s.dq(i).v;
    enable_s(i) <= pins_s.dq(i).en;
  end generate;

  dut: nsl_qspi.xip.axi4_mm_qspi_xip
    generic map(config_c => axi_config_c)
    port map(clock_i => clock_s, reset_n_i => reset_n_s,
             config_i => config_s, axi_i => axi_s.m, axi_o => axi_s.s,
             cmd_o => command_s.req, cmd_i => command_s.ack,
             rsp_i => response_s.req, rsp_o => response_s.ack);
  wire: nsl_qspi.transactor.qspi_framed_transactor
    port map(clock_i => clock_s, reset_n_i => reset_n_s,
             qspi_o => pins_s, qspi_i => pin_input_s,
             cmd_i => command_s.req, cmd_o => command_s.ack,
             rsp_o => response_s.req, rsp_i => response_s.ack);
  flash: work.qspi_test_support.qspi_flash_model
    port map(cs_n_i => pins_s.cs_n, sck_i => pins_s.sck,
             dq_i => dq_s, enable_i => enable_s, dq_o => pin_input_s.dq,
             opcode_i => opcode_s, address_i => flash_address_s,
             address_bytes_i => address_bytes_s, address_lanes_i => address_lanes_s,
             data_lanes_i => data_lanes_s, dummy_cycles_i => dummy_s,
             data_bytes_i => data_bytes_s, half_period_i => half_period_s,
             completed_o => completed_s);

  timeout: process
  begin
    wait for 2 ms;
    assert done_s report "QSPI XIP timeout" severity failure;
    wait;
  end process;

  stimulus: process
    procedure tick is
    begin
      wait until rising_edge(clock_s);
      wait until falling_edge(clock_s);
    end procedure;

    procedure read_burst(
      constant address: in unsigned(31 downto 0);
      constant flash_address: in unsigned(31 downto 0);
      constant beats: in positive;
      constant id: in std_ulogic_vector(3 downto 0);
      constant stall: in boolean := false;
      constant snapshot_config: in boolean := false;
      constant size_l2: in natural := 2;
      constant burst_mode: in burst_enum_t := BURST_INCR) is
      variable held_v: read_data_t;
      variable expected_v: byte_string(0 to 3);
      variable fa_v, axi_address_v: unsigned(31 downto 0);
      variable byte_count_v, lane_v: natural;
    begin
      byte_count_v := 2**size_l2;
      fa_v := flash_address;
      axi_address_v := address;
      flash_address_s <= fa_v;
      data_bytes_s <= byte_count_v;
      axi_s.m.ar <= nsl_amba.axi4_mm.address(
        axi_config_c, id => id, addr => address,
        len_m1 => to_unsigned(beats-1, axi_config_c.len_width),
        size_l2 => to_unsigned(size_l2, 3), burst => burst_mode);
      loop
        wait until rising_edge(clock_s);
        exit when axi_s.s.ar.ready = '1';
      end loop;
      wait until falling_edge(clock_s);
      axi_s.m.ar <= address_defaults(axi_config_c);
      if snapshot_config then
        config_s.quad_enable <= not config_s.quad_enable;
        config_s.flash_offset <= x"70000000";
        config_s.divider <= 7;
      end if;
      for beat in 0 to beats-1 loop
        axi_s.m.r <= accept(axi_config_c, not stall);
        loop
          wait until rising_edge(clock_s);
          exit when axi_s.s.r.valid = '1';
        end loop;
        held_v := axi_s.s.r;
        wait until falling_edge(clock_s);
        if stall then
          axi_s.m.r <= accept(axi_config_c, false);
          for i in 1 to 5 loop
            tick;
            assert axi_s.s.r = held_v report "AXI R changed under backpressure" severity failure;
          end loop;
          axi_s.m.r <= accept(axi_config_c, true);
        end if;
        expected_v := (others => x"00");
        lane_v := to_integer(axi_address_v(1 downto 0));
        for lane in 0 to byte_count_v-1 loop
          expected_v(lane_v + lane) := memory_byte(fa_v + lane);
        end loop;
        assert nsl_amba.axi4_mm.id(axi_config_c, held_v) = id
          report "XIP did not preserve ARID" severity failure;
        assert nsl_amba.axi4_mm.resp(axi_config_c, held_v) = RESP_OKAY
          report "XIP read returned an error" severity failure;
        assert nsl_amba.axi4_mm.bytes(axi_config_c, held_v) = expected_v
          report "XIP read data or byte-lane ordering mismatch" severity failure;
        assert nsl_amba.axi4_mm.is_last(axi_config_c, held_v) = (beat = beats-1)
          report "XIP RLAST mismatch" severity failure;
        tick;
        if burst_mode = BURST_INCR then
          fa_v := fa_v + byte_count_v;
          axi_address_v := axi_address_v + byte_count_v;
        end if;
        flash_address_s <= fa_v;
      end loop;
      axi_s.m.r <= accept(axi_config_c, false);
    end procedure;

    procedure error_read(
      constant address: in unsigned(31 downto 0);
      constant burst: in burst_enum_t := BURST_INCR;
      constant lock: in lock_enum_t := LOCK_NORMAL) is
      variable before_v: natural;
    begin
      before_v := completed_s;
      axi_s.m.ar <= nsl_amba.axi4_mm.address(
        axi_config_c, id => "0110", addr => address,
        len_m1 => to_unsigned(1, axi_config_c.len_width),
        size_l2 => to_unsigned(2, 3),
        burst => burst, lock => lock);
      loop
        wait until rising_edge(clock_s);
        exit when axi_s.s.ar.ready = '1';
      end loop;
      wait until falling_edge(clock_s);
      axi_s.m.ar <= address_defaults(axi_config_c);
      axi_s.m.r <= accept(axi_config_c, true);
      for beat in 0 to 1 loop
        loop
          wait until rising_edge(clock_s);
          exit when axi_s.s.r.valid = '1';
        end loop;
        assert nsl_amba.axi4_mm.resp(axi_config_c, axi_s.s.r) = RESP_SLVERR
          report "Unsupported AXI read did not return SLVERR" severity failure;
        assert nsl_amba.axi4_mm.is_last(axi_config_c, axi_s.s.r) = (beat = 1)
          report "Error burst RLAST mismatch" severity failure;
        wait until falling_edge(clock_s);
      end loop;
      axi_s.m.r <= accept(axi_config_c, false);
      assert completed_s = before_v report "Rejected read accessed QSPI" severity failure;
    end procedure;

    procedure error_write(constant data_first: in boolean) is
      variable held_v: write_response_t;

      procedure send_data is
      begin
        for beat in 0 to 1 loop
          axi_s.m.w <= write_data(
            axi_config_c, value => to_unsigned(16#1000# + beat, 32),
            last => beat = 1);
          loop
            wait until rising_edge(clock_s);
            exit when axi_s.s.w.ready = '1';
          end loop;
          wait until falling_edge(clock_s);
          axi_s.m.w <= write_data_defaults(axi_config_c);
        end loop;
      end procedure;
    begin
      if data_first then
        send_data;
      end if;
      axi_s.m.aw <= nsl_amba.axi4_mm.address(
        axi_config_c, id => "1101", addr => x"00000100",
        len_m1 => to_unsigned(1, axi_config_c.len_width),
        size_l2 => to_unsigned(2, 3));
      loop
        wait until rising_edge(clock_s);
        exit when axi_s.s.aw.ready = '1';
      end loop;
      wait until falling_edge(clock_s);
      axi_s.m.aw <= address_defaults(axi_config_c);
      if not data_first then
        send_data;
      end if;
      axi_s.m.b <= accept(axi_config_c, false);
      loop
        wait until rising_edge(clock_s);
        exit when axi_s.s.b.valid = '1';
      end loop;
      held_v := axi_s.s.b;
      wait until falling_edge(clock_s);
      for i in 1 to 4 loop
        tick;
        assert axi_s.s.b = held_v report "AXI B changed under backpressure" severity failure;
      end loop;
      assert nsl_amba.axi4_mm.resp(axi_config_c, held_v) = RESP_SLVERR
        and nsl_amba.axi4_mm.id(axi_config_c, held_v) = "1101"
        report "Write rejection response/ID mismatch" severity failure;
      axi_s.m.b <= accept(axi_config_c, true);
      tick;
      axi_s.m.b <= accept(axi_config_c, false);
    end procedure;
  begin
    axi_s.m.aw <= address_defaults(axi_config_c);
    axi_s.m.w <= write_data_defaults(axi_config_c);
    axi_s.m.b <= accept(axi_config_c, false);
    axi_s.m.ar <= address_defaults(axi_config_c);
    axi_s.m.r <= accept(axi_config_c, false);
    wait for 30 ns;
    assert pins_s.cs_n = '1' and command_s.req.valid = '0'
      report "Reset generated flash traffic" severity failure;
    reset_n_s <= '1';
    tick;

    error_read(x"00000100");
    config_s <= (
      enabled => true, quad_enable => false, flash_offset => x"00100000", divider => 2,
      single_profile => (x"0b", false, false, 8),
      quad_profile => (x"eb", true, true, 6));
    opcode_s <= x"0b";
    flash_address_s <= x"00100120";
    dummy_s <= 8;
    half_period_s <= 20 ns;
    read_burst(x"00000120", x"00100120", 3, "1010", true);
    assert completed_s = 3 report "Expected one flash frame per AXI beat" severity failure;

    read_burst(x"00000125", x"00100125", 6, "0001",
               size_l2 => 0);
    read_burst(x"0000012a", x"0010012a", 3, "0010",
               size_l2 => 1);
    read_burst(x"0000012c", x"0010012c", 3, "0100",
               size_l2 => 1, burst_mode => BURST_FIXED);
    assert completed_s = 15 report "Narrow/FIXED reads did not issue expected frames" severity failure;

    config_s.quad_enable <= true;
    opcode_s <= x"eb";
    address_bytes_s <= 4;
    address_lanes_s <= 4;
    data_lanes_s <= 4;
    dummy_s <= 6;
    read_burst(x"00000200", x"00100200", 3, "0011", false, true);
    assert completed_s = 18 report "Multi-beat snapshot read did not complete" severity failure;

    -- Restore after the deliberate mid-transaction configuration change.
    config_s <= (
      enabled => true, quad_enable => true, flash_offset => x"00100000", divider => 2,
      single_profile => (x"0b", false, false, 8),
      quad_profile => (x"eb", true, true, 6));
    error_read(x"00000102");
    error_read(x"00000100", BURST_WRAP);
    error_read(x"00000100", BURST_INCR, LOCK_EXCLUSIVE);
    error_read(x"00000ffc");

    -- Selected 24-bit profile cannot represent the offset-adjusted address.
    config_s <= (
      enabled => true, quad_enable => false, flash_offset => x"00fffff0", divider => 2,
      single_profile => (x"03", false, false, 0),
      quad_profile => (x"eb", true, true, 6));
    error_read(x"00000020");

    -- 32-bit profile still rejects offset addition and AXI address overflow.
    config_s <= (
      enabled => true, quad_enable => true, flash_offset => x"fffffff0", divider => 2,
      single_profile => (x"03", false, false, 0),
      quad_profile => (x"eb", true, true, 6));
    error_read(x"00000020");
    config_s.flash_offset <= x"00000000";
    error_read(x"fffffffc");
    error_write(true);
    error_write(false);

    report "QSPI XIP: profiles, narrow/FIXED bursts, snapshot, overflow and stalls passed";
    done_s <= true;
    nsl_simulation.control.terminate(0);
    wait;
  end process;
end architecture;
