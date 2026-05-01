library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb is
end tb;

library nsl_jtag, nsl_amba, nsl_simulation, nsl_data, nsl_event, nsl_math;
architecture arch of tb is

  constant clock_period : time := 10 ns;
  constant ir_len_c : natural := 8;

  constant cfg_c: nsl_amba.axi4_stream.config_t := nsl_amba.axi4_stream.config(1, last => true);

  signal s_cmd     : nsl_amba.axi4_stream.bus_t;
  signal s_rsp     : nsl_amba.axi4_stream.bus_t;
  signal s_rsp_pre : nsl_amba.axi4_stream.bus_t;

  signal s_tap_ir : std_ulogic_vector(ir_len_c - 1 downto 0);
  signal s_tap_reset, s_tap_run, s_tap_dr_capture, s_tap_dr_shift, s_tap_dr_update, s_tap_dr_in, s_tap_dr_out : std_ulogic;
  signal ate_o : nsl_jtag.jtag.jtag_ate_o;
  signal ate_i : nsl_jtag.jtag.jtag_ate_i;
  signal tap_o : nsl_jtag.jtag.jtag_tap_o;
  signal tap_i : nsl_jtag.jtag.jtag_tap_i;

  signal s_idcode_out, s_idcode_selected : std_ulogic;
  signal s_bypass_out, s_bypass_selected : std_ulogic;

  signal s_clk, s_resetn : std_ulogic;
  signal s_done : std_ulogic_vector(0 to 0);

  signal tick_s, tick_ms_s : std_ulogic;
  constant tick_divisor : unsigned(7 downto 0) := (others => '1');
  constant tick_ms_divisor : unsigned := nsl_math.arith.to_unsigned_auto(10e7/1000);


  shared variable cmd_q, rsp_q : nsl_amba.axi4_stream.frame_queue_root_t;

begin

  ate_i <= nsl_jtag.jtag.to_ate(tap_o);
  tap_i <= nsl_jtag.jtag.to_tap(ate_o);

  tap : nsl_jtag.tap.tap_port
  generic map(
    ir_len => ir_len_c
  )
  port map(
    jtag_i                => tap_i,
    jtag_o                => tap_o,

    default_instruction_i => "00000010",

    ir_o                  => s_tap_ir,
    ir_out_i              => "000000",
    reset_o               => s_tap_reset,
    run_o                 => s_tap_run,
    dr_capture_o          => s_tap_dr_capture,
    dr_shift_o            => s_tap_dr_shift,
    dr_update_o           => s_tap_dr_update,
    dr_tdi_o              => s_tap_dr_in,
    dr_tdo_i              => s_tap_dr_out
  );

  idcode : nsl_jtag.tap.tap_dr
  generic map(
    ir_len => ir_len_c,
    dr_len => 32
  )
  port map(
    tck_i        => tap_i.tck,
    tdi_i        => s_tap_dr_in,
    tdo_o        => s_idcode_out,

    match_ir_i   => "00010001",
    current_ir_i => s_tap_ir,
    active_o     => s_idcode_selected,

    dr_capture_i => s_tap_dr_capture,
    dr_shift_i   => s_tap_dr_shift,
    value_o      => open,
    value_i      => x"87654321"
  );

  bypass : nsl_jtag.tap.tap_dr
  generic map(
    ir_len => ir_len_c,
    dr_len => 1
  )
  port map(
    tck_i        => tap_i.tck,
    tdi_i        => s_tap_dr_in,
    tdo_o        => s_bypass_out,

    match_ir_i   => "00001111",
    current_ir_i => s_tap_ir,
    active_o     => s_bypass_selected,

    dr_capture_i => s_tap_dr_capture,
    dr_shift_i   => s_tap_dr_shift,
    value_o      => open,
    value_i      => "0"
  );

  tdo_gen: process(s_idcode_selected, s_idcode_out,
                   s_bypass_selected, s_bypass_out)
  begin
    s_tap_dr_out <= '-';

    if s_idcode_selected = '1' then
      s_tap_dr_out <= s_idcode_out;
    elsif s_bypass_selected = '1' then
      s_tap_dr_out <= s_bypass_out;
    end if;
  end process;

  dut: nsl_jtag.cbor_transactor.axi4stream_cbor_ate
  generic map(
   stream_config_c => cfg_c
  )
  port map(
    clock_i   => s_clk,
    reset_n_i => s_resetn,

    tick_i    => tick_s,
    tick_ms_i => tick_ms_s,

    cmd_i     => s_cmd.m,
    cmd_o     => s_cmd.s,

    rsp_o     => s_rsp_pre.m,
    rsp_i     => s_rsp_pre.s,

    jtag_o    => ate_o,
    jtag_i    => ate_i
  );

  rsp_pacer : nsl_amba.stream_traffic.axi4_stream_pacer
  generic map(
    config_c      => cfg_c,
    probability_c => 0.1
  )
  port map(
    clock_i   => s_clk,
    reset_n_i => s_resetn,

    in_i      => s_rsp_pre.m,
    in_o      => s_rsp_pre.s,

    out_o     => s_rsp.m,
    out_i     => s_rsp.s
  );

  driver : nsl_simulation.driver.simulation_driver
  generic map(
    clock_count => 1,
    reset_count => 1,
    done_count  => 1
  )
  port map(
    clock_period(0)   => 10 ns,
    reset_duration(0) => 30 ns,
    reset_n_o(0)      => s_resetn,
    clock_o(0)        => s_clk,
    done_i            => s_done
  );

  tick_gen : nsl_event.tick.tick_generator_integer
    port map(
      clock_i     => s_clk,
      reset_n_i   => s_resetn,
      period_m1_i => tick_divisor,
      tick_o      => tick_s
    );

  tick_ms_gen : nsl_event.tick.tick_generator_integer
    port map(
      clock_i     => s_clk,
      reset_n_i   => s_resetn,
      period_m1_i => tick_ms_divisor,
      tick_o      => tick_ms_s
    );

  stim: process
    variable check_status : boolean := false;
    variable pass_count, fail_count : integer := 0;
    variable dummy_frame : nsl_amba.axi4_stream.frame_t;
  begin

    nsl_amba.axi4_stream.frame_queue_init(cmd_q);
    nsl_amba.axi4_stream.frame_queue_init(rsp_q);

    -- Let FSM reach IDLE
    wait for 50 ns;

    nsl_simulation.logging.log(
      level => nsl_simulation.logging.LOG_LEVEL_INFO,
      message => "======================================",
      color => nsl_simulation.logging.LOG_COLOR_CYAN
    );
    nsl_simulation.logging.log(
      level => nsl_simulation.logging.LOG_LEVEL_INFO,
      message => "JTAG CBOR TRANSACTOR TEST SUITE",
      color => nsl_simulation.logging.LOG_COLOR_CYAN
    );
    nsl_simulation.logging.log(
      level => nsl_simulation.logging.LOG_LEVEL_INFO,
      message => "======================================",
      color => nsl_simulation.logging.LOG_COLOR_CYAN
    );


    -- Test 1: Reset command (tag 10) - verify s_tap_reset goes high
    -- 81 = array(1), ca0a = reset(10 cycles)
    nsl_amba.axi4_stream.frame_queue_put(cmd_q, nsl_data.bytestream.from_suv(x"81ca0a"));
    wait until s_tap_reset = '1';
    check_status := s_tap_reset = '1';
    nsl_simulation.logging.log_test_result("TAP: Reset signal asserted", check_status, pass_count, fail_count);
    nsl_amba.axi4_stream.frame_queue_get(rsp_q, dummy_frame, timeout => 1 ms);

    -- wait for 50 us;

    -- Test 2: Run command (positive integer) - verify s_tap_run goes high
    -- 81 = array(1), 0a = run(10 cycles)
    nsl_amba.axi4_stream.frame_queue_put(cmd_q, nsl_data.bytestream.from_suv(x"810a"));
    wait until s_tap_run = '1';
    check_status := s_tap_run = '1';
    nsl_simulation.logging.log_test_result("TAP: Run signal asserted", check_status, pass_count, fail_count);
    nsl_amba.axi4_stream.frame_queue_get(rsp_q, dummy_frame, timeout => 1 ms);

    -- wait for 50 us;

    -- Test 3: DR-Capture command (simple value 1) - verify s_tap_dr_capture pulses
    -- 81 = array(1), e1 = simple(1) = dr-capture
    nsl_amba.axi4_stream.frame_queue_put(cmd_q, nsl_data.bytestream.from_suv(x"81e1"));
    wait until s_tap_dr_capture = '1';
    check_status := s_tap_dr_capture = '1';
    nsl_simulation.logging.log_test_result("TAP: DR-Capture signal asserted", check_status, pass_count, fail_count);
    nsl_amba.axi4_stream.frame_queue_get(rsp_q, dummy_frame, timeout => 1 ms);

    -- wait for 50 us;

    -- Test 4: DR-Shift - verify s_tap_dr_shift goes high during shift
    -- First do dr-capture, then shift 8 bits
    -- 82 = array(2), e1 = dr-capture, c808 = shift_cycles(8)
    nsl_amba.axi4_stream.frame_queue_put(cmd_q, nsl_data.bytestream.from_suv(x"82e1c808"));
    wait until s_tap_dr_shift = '1';
    check_status := s_tap_dr_shift = '1';
    nsl_simulation.logging.log_test_result("TAP: DR-Shift signal asserted", check_status, pass_count, fail_count);
    nsl_amba.axi4_stream.frame_queue_get(rsp_q, dummy_frame, timeout => 1 ms);

    -- wait for 50 us;

    -- Test 5: Run-time command (tag 11) - verify s_tap_run goes high for duration
    -- 81 = array(1), cb01 = run-time(1 ms) 
    nsl_amba.axi4_stream.frame_queue_put(cmd_q, nsl_data.bytestream.from_suv(x"81cb01"));
    wait until s_tap_run = '1' for 1 ms;
    check_status := s_tap_run = '1';
    nsl_simulation.logging.log_test_result("TAP: Run-time signal asserted", check_status, pass_count, fail_count);
    nsl_amba.axi4_stream.frame_queue_get(rsp_q, dummy_frame, timeout => 3 ms);

    -- wait for 50 us;

    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1 => nsl_data.bytestream.from_suv(x"87ca0602e2c9411103e1c81820"),
                                              data2 => nsl_data.bytestream.from_suv(x"9f59000421436587ff"),
                                              check_status => check_status,
                                              dt      => clock_period,
                                              timeout => clock_period*2000000,
                                              sev     => warning);
    nsl_simulation.logging.log_test_result("IDCODE read", check_status, pass_count, fail_count);

    -- Test 6: Shift with no TDI using shift_cycles (tag 8)
    -- Command: reset(6), run(2), ir-capture, shift-no-tdo(0x11=IDCODE), run(3), dr-capture, shift_cycles(32)
    -- 87 = array(7), ca06 = reset(6), 02 = run(2), e2 = ir-capture, c94111 = shift-no-tdo(0x11),
    -- 03 = run(3), e1 = dr-capture, c81820 = shift_cycles(32)
    -- Response: bstr with 4 bytes of IDCODE = 0x87654321 (LSB first: 21 43 65 87)
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1 => nsl_data.bytestream.from_suv(x"87ca0602e2c9411103e1c81820"),
                                              data2 => nsl_data.bytestream.from_suv(x"9f59000421436587ff"),
                                              check_status => check_status,
                                              dt      => clock_period,
                                              timeout => clock_period*2000000,
                                              sev     => warning);
    nsl_simulation.logging.log_test_result("Shift with no TDI (32 cycles)", check_status, pass_count, fail_count);

    -- Test 7: Shift with minus and no TDO (minus 3 - do not shift last 3 bits of payload)
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1 => nsl_data.bytestream.from_suv(x"87ca0602e2c3c9411103e1c81820"),
                                              data2 => nsl_data.bytestream.from_hex("9f590004--------ff"),
                                              check_status => check_status,
                                              dt      => clock_period,
                                              timeout => clock_period*2000000,
                                              sev     => warning);
    nsl_simulation.logging.log_test_result("Minus with no TDO", check_status, pass_count, fail_count);

    -- Test 8: Run for 3ms (response is empty indefinite array 9fff)
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1 => nsl_data.bytestream.from_suv(x"81CB03"),
                                              data2 => nsl_data.bytestream.from_suv(x"9fff"),
                                              check_status => check_status,
                                              dt      => clock_period,
                                              timeout => clock_period*2000000 + 3 ms,
                                              sev     => warning);
    nsl_simulation.logging.log_test_result("Run for 3ms", check_status, pass_count, fail_count);
   
    -- Test 9 (Large shift)
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1 => nsl_data.bytestream.from_suv(x"9fc95903ffE8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8E8ff"),
                                              data2 => nsl_data.bytestream.from_suv(x"9fff"),
                                              check_status => check_status,
                                              dt      => clock_period,
                                              timeout => clock_period*2000000 + 4 ms,
                                              sev     => warning);
    nsl_simulation.logging.log_test_result("Large shift operation", check_status, pass_count, fail_count);

    -- Test 10: Read 16 bits of IDCODE (similar to test 1 but fewer bits)
    -- Command: reset(6), run(2), ir-capture, shift-no-tdo(0x11=IDCODE), run(3), dr-capture, shift_cycles(16)
    -- 03 = run(3), e1 = dr-capture, c810 = shift_cycles(16)
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1 => nsl_data.bytestream.from_suv(x"87ca0602e2c9411103e1c810"),
                                              data2 => nsl_data.bytestream.from_suv(x"9f5900022143ff"),
                                              check_status => check_status,
                                              dt      => clock_period,
                                              timeout => clock_period*2000000,
                                              sev     => warning);
    nsl_simulation.logging.log_test_result("IDCODE read (16 bits)", check_status, pass_count, fail_count);

    -- Test 11: BYPASS mode
    -- Command: reset(6), run(2), ir-capture, shift-no-tdo(0x0F=BYPASS), run(3), dr-capture, shift_cycles(8)
    -- BYPASS is a 1-bit register, shift 8 bits of zeros (shift_cycles with no TDI data)
    -- Response: bstr with 1 byte = 0x00 (shifted zeros through BYPASS)
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1 => nsl_data.bytestream.from_suv(x"87ca0602e2c9410f03e1c808"),
                                              data2 => nsl_data.bytestream.from_suv(x"9f59000100ff"),
                                              check_status => check_status,
                                              dt      => clock_period,
                                              timeout => clock_period*2000000,
                                              sev     => warning);
    nsl_simulation.logging.log_test_result("BYPASS mode (8 cycles)", check_status, pass_count, fail_count);

    -- Test 12: Shift minus-7 (#6.7) - do not shift the last 7 bits of the argument
    -- After BYPASS is still loaded, do dr-capture, then shift 1 bit
    -- Response: bstr with 1 byte, TDO depends on BYPASS state
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1 => nsl_data.bytestream.from_suv(x"83e1c741aa00"),
                                              data2 => nsl_data.bytestream.from_suv(x"9f590001" & "-------0" & x"ff"),
                                              check_status => check_status,
                                              dt      => clock_period,
                                              timeout => clock_period*2000000,
                                              sev     => warning);
    nsl_simulation.logging.log_test_result("Shift minus-7 (1 bit)", check_status, pass_count, fail_count);

    -- Test 13: Shift minus-1 (#6.1) - do not shft the last bit of the argument
    -- After BYPASS is still loaded, do dr-capture, then shift 7 bit
    -- Response: bstr with 1 byte, TDO depends on BYPASS state
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1 => nsl_data.bytestream.from_suv(x"83e1c141aa00"),
                                              data2 => nsl_data.bytestream.from_suv(x"9f590001" & "0101010-" & x"ff"),
                                              check_status => check_status,
                                              dt      => clock_period,
                                              timeout => clock_period*2000000,
                                              sev     => warning);
    nsl_simulation.logging.log_test_result("Shift minus-1 (7 bit)", check_status, pass_count, fail_count);

    -- Test 14: Shift minus-4 (#6.4) - do not shift the last 4 bits of the argument
    -- Response: bstr with 1 byte, TDO depends on BYPASS state
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1 => nsl_data.bytestream.from_suv(x"83e1c441aa00"),
                                              data2 => nsl_data.bytestream.from_suv(x"9f590001" & "----010-" & x"ff"),
                                              check_status => check_status,
                                              dt      => clock_period,
                                              timeout => clock_period*2000000,
                                              sev     => warning);
    nsl_simulation.logging.log_test_result("Shift minus-4 (4 bits)", check_status, pass_count, fail_count);

    -- Test 15: IR scan with TDO capture (not using shift-no-tdo)
    -- Reset, run, ir-capture, shift IR with TDO capture (not c9 tagged)
    -- Response: bstr with captured IR output = 0x01 (default IR value after reset is 0x02,
    -- shifted out LSB first during IR scan, giving captured value 0x01)
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1 => nsl_data.bytestream.from_suv(x"85ca0602e2411100"),
                                              data2 => nsl_data.bytestream.from_suv(x"9f59000101ff"),
                                              check_status => check_status,
                                              dt      => clock_period,
                                              timeout => clock_period*2000000,
                                              sev     => warning);
    nsl_simulation.logging.log_test_result("IR scan with TDO capture", check_status, pass_count, fail_count);

    -- Test 16: Shift cycles non-multiple of 8 (#6.8(12)) - 12 bits = 1.5 bytes
    -- After IDCODE is loaded from previous tests, do dr-capture, then shift 12 bits
    -- IDCODE = 0x87654321, lower 12 bits = 0x321
    -- Response: bstr with 2 bytes: 0x21 (bits 7..0), 0x03 (bits 11..8, masked)
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1 => nsl_data.bytestream.from_suv(x"87ca0602e2c9411103e1c80c"),
                                              data2 => nsl_data.bytestream.from_suv(x"9f5900022103ff"),
                                              check_status => check_status,
                                              dt      => clock_period,
                                              timeout => clock_period*2000000,
                                              sev     => warning);
    nsl_simulation.logging.log_test_result("Shift cycles non-multiple of 8 (12 bits)", check_status, pass_count, fail_count);

    -- Test 17: Extended reset cycles (larger count)
    -- Response: empty (9fff)
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1 => nsl_data.bytestream.from_suv(x"82ca186400"),
                                              data2 => nsl_data.bytestream.from_suv(x"9fff"),
                                              check_status => check_status,
                                              dt      => clock_period,
                                              timeout => clock_period*2000000,
                                              sev     => warning);
    nsl_simulation.logging.log_test_result("Extended reset (100 cycles)", check_status, pass_count, fail_count);

    -- Test 18: Back-to-back DR shifts (multiple shifts in one command)
    -- Reset, run, load IDCODE, run, dr-capture, shift 8 bits x3, run
    -- Response: 3 bstr entries (each 1 byte with 2-byte length encoding)
    -- IDCODE = 0x87654321, shifted LSB first: 0x21, 0x43, 0x65
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1 => nsl_data.bytestream.from_suv(x"89ca0602e2c94111e1c808c808c80800"),
                                              data2 => nsl_data.bytestream.from_suv(x"9f590001215900014359000165ff"),
                                              check_status => check_status,
                                              dt      => clock_period,
                                              timeout => clock_period*2000000,
                                              sev     => warning);
    nsl_simulation.logging.log_test_result("Back-to-back DR shifts", check_status, pass_count, fail_count);

    wait for 100 us;

    nsl_simulation.logging.log_test_suite_summary("JTAG CBOR TRANSACTOR TESTS", pass_count, fail_count);

    if fail_count > 0 then
      nsl_simulation.control.terminate(1);
    else
      nsl_simulation.control.terminate(0);
    end if;
  end process;

  cmd_queue: process
  begin
    -- Let FSM reach IDLE and queues be initialized
    wait for 70 ns;
    nsl_simulation.logging.log(level => nsl_simulation.logging.LOG_LEVEL_INFO, message => "Going to run frame_queue_master", color => nsl_simulation.logging.LOG_COLOR_MAGENTA);
    nsl_amba.axi4_stream.frame_queue_master(cfg => cfg_c, root => cmd_q, clock => s_clk,
                                            stream_i => s_cmd.s, stream_o => s_cmd.m, dt => clock_period);
  end process;
  
  rsp_queue: process
  begin
    -- Let FSM reach IDLE and queues be initialized
    wait for 70 ns;
    nsl_simulation.logging.log(level => nsl_simulation.logging.LOG_LEVEL_INFO, message => "Going to run frame_queue_slave", color => nsl_simulation.logging.LOG_COLOR_YELLOW);
    nsl_amba.axi4_stream.frame_queue_slave(cfg => cfg_c, root => rsp_q, clock => s_clk,
                                           stream_i => s_rsp.m, stream_o => s_rsp.s, dt => clock_period);   
  end process;

end architecture;
