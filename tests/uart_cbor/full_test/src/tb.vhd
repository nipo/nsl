library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_uart, nsl_amba, nsl_data, nsl_simulation;

entity tb is
end;

architecture arch of tb is
  constant c_clock_period : time := 10 ns;
  constant c_cfg : nsl_amba.axi4_stream.config_t := nsl_amba.axi4_stream.config(bytes => 1, last => true);
  
  type uart_t is
  record
    tx : std_ulogic;
    cts: std_ulogic;
    rx : std_ulogic;
    rts: std_ulogic;
  end record;

  signal s_uart: uart_t;
  signal s_clk, s_rst_n: std_ulogic;

  signal s_cmd, s_rsp : nsl_amba.axi4_stream.bus_t;

  shared variable cmd_q, rsp_q: nsl_amba.axi4_stream.frame_queue_root_t;
begin

  dut : nsl_uart.transactor.cbor_controller
    generic map(
      system_clock_c => 10e7,
      axi_s_cfg_c => c_cfg,
      stop_count_c => 1,
      parity_c => nsl_uart.serdes.PARITY_NONE,
      handshake_active_c => '0',
      divisor_c => to_unsigned(868, 32), -- 115200 bds
      timeout_c => to_unsigned(2000, 32), -- timeout in bit time
      bstr_max_size_c => 120
      )
    port map(
      reset_n_i => s_rst_n,
      clock_i => s_clk,

      tx_o  => s_uart.tx,
      cts_i => s_uart.cts,
      rx_i  => s_uart.rx,
      rts_o => s_uart.rts,

      cmd_i => s_cmd.m,
      cmd_o => s_cmd.s,
      rsp_o => s_rsp.m,
      rsp_i => s_rsp.s
      );

  s_uart.rx <= s_uart.tx;

  driver : nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => 1
      )
    port map(
      clock_period(0) => c_clock_period,
      reset_duration(0) => c_clock_period*2,
      reset_n_o(0) => s_rst_n,
      clock_o(0) => s_clk,
      done_i(0) => '0'
      );
  
  stim: process
    variable check_status : boolean := false;
    variable pass_count, fail_count : integer := 0;
  begin
    s_uart.cts <= '1';  -- CTS active = clear to send

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
      message => "UART CBOR TRANSACTOR TEST SUITE",
      color => nsl_simulation.logging.LOG_COLOR_CYAN
    );
    nsl_simulation.logging.log(
      level => nsl_simulation.logging.LOG_LEVEL_INFO,
      message => "======================================",
      color => nsl_simulation.logging.LOG_COLOR_CYAN
    );
    -- nsl_amba.axi4_stream.frame_queue_put(root => cmd_q,
    --                                      data => nsl_data.bytestream.from_suv(x"A369666C6F772D6374726C6363747366706172697479616569626175642D72617465192d00"));
    -- There's no response to this command, so the configuration changes would
    -- need to be asserted. Can't do that from here.
    -- assert()
    -- wait for 80 ns;
    -- nsl_simulation.logging.log(level => nsl_simulation.logging.LOG_LEVEL_INFO,
    --                            message => "============================================== #0 CONFIGURATION SUCCESSFULLY SET" & LF,
    --                            color => nsl_simulation.logging.LOG_COLOR_GREEN);   

    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1 => nsl_data.bytestream.from_suv(x"A369666C6F772D6374726C6363747366706172697479616569626175642D726174651a0001c200"),
                                              data2 => nsl_data.bytestream.from_suv(x"F5"),
                                              check_status => check_status,
                                              dt      => c_clock_period,
                                              timeout => c_clock_period*1500000,
                                              sev     => warning);
    nsl_simulation.logging.log_test_result("Set configuration", check_status, pass_count, fail_count);   
    

    -- Send "Hello world!" message - with single FSM, F5 comes first then loopback data
    nsl_amba.axi4_stream.frame_queue_put(root => cmd_q,
                                         data => nsl_data.bytestream.from_suv(x"4C48656C6C6F20776F726C6421"));

    -- First expect TX confirmation (F5)
    nsl_amba.axi4_stream.frame_queue_check(root => rsp_q,
                                           data => nsl_data.bytestream.from_suv(x"f5"),
                                           check_status => check_status,
                                           dt      => c_clock_period,
                                           timeout => c_clock_period*1500000,
                                           sev     => warning);
    nsl_simulation.logging.log_test_result("Hello world TX confirmation", check_status, pass_count, fail_count);

    -- Then expect RX loopback data
    nsl_amba.axi4_stream.frame_queue_check(root => rsp_q,
                                           data => nsl_data.bytestream.from_suv(x"59000C48656C6C6F20776F726C6421"),
                                           check_status => check_status,
                                           dt      => c_clock_period,
                                           timeout => c_clock_period*25000000,
                                           sev     => warning);
    nsl_simulation.logging.log_test_result("Hello world RX loopback", check_status, pass_count, fail_count);    

    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1 => nsl_data.bytestream.from_suv(x"F6"),
                                              data2 => nsl_data.bytestream.from_suv(x"A369666C6F772D6374726C6363747366706172697479616569626175642D726174651a0001c200"),
                                              check_status => check_status,
                                              dt      => c_clock_period,
                                              timeout => c_clock_period*1500000,
                                              sev     => warning);
    nsl_simulation.logging.log_test_result("Retrieve configuration", check_status, pass_count, fail_count);

    -- Test 5: Single byte message
    -- Note: For short messages, TX confirmation (F5) arrives BEFORE RX loopback data
    -- because TX state machine finishes when data is queued, not when transmitted
    -- Command: bstr(1 byte) = 41 xx
    nsl_amba.axi4_stream.frame_queue_put(root => cmd_q,
                                         data => nsl_data.bytestream.from_suv(x"41aa"));

    -- First expect TX confirmation (F5)
    nsl_amba.axi4_stream.frame_queue_check(root => rsp_q,
                                           data => nsl_data.bytestream.from_suv(x"f5"),
                                           check_status => check_status,
                                           dt      => c_clock_period,
                                           timeout => c_clock_period*1500000,
                                           sev     => warning);
    nsl_simulation.logging.log_test_result("Single byte TX confirmation", check_status, pass_count, fail_count);

    -- Then expect RX loopback data: bstr_hdr(1) + data = 59 00 01 xx
    nsl_amba.axi4_stream.frame_queue_check(root => rsp_q,
                                           data => nsl_data.bytestream.from_suv(x"590001aa"),
                                           check_status => check_status,
                                           dt      => c_clock_period,
                                           timeout => c_clock_period*25000000,
                                           sev     => warning);
    nsl_simulation.logging.log_test_result("Single byte RX loopback", check_status, pass_count, fail_count);

    -- Test 7: Configure no parity
    -- Command: map(3) {flow-ctrl: "cts", parity: "n", baud-rate: 9600}
    -- A3 69 "flow-ctrl" 63 "cts" 66 "parity" 61 "n" 69 "baud-rate" 19 2580
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1 => nsl_data.bytestream.from_suv(x"A369666C6F772D6374726C636374736670617269747961" & x"6e" & x"69626175642D726174651a0001c200"),
                                              data2 => nsl_data.bytestream.from_suv(x"F5"),
                                              check_status => check_status,
                                              dt      => c_clock_period,
                                              timeout => c_clock_period*1500000,
                                              sev     => warning);
    nsl_simulation.logging.log_test_result("Configure no parity", check_status, pass_count, fail_count);

    -- Test 8: Verify parity change via query
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1 => nsl_data.bytestream.from_suv(x"F6"),
                                              data2 => nsl_data.bytestream.from_suv(x"A369666C6F772D6374726C636374736670617269747961" & x"6e" & x"69626175642D726174651a0001c200"),
                                              check_status => check_status,
                                              dt      => c_clock_period,
                                              timeout => c_clock_period*1500000,
                                              sev     => warning);
    nsl_simulation.logging.log_test_result("Verify no parity config", check_status, pass_count, fail_count);

    -- Test 9: Send message with no parity ("TEST" = 4 bytes)
    -- With single FSM, F5 comes first, then RX loopback data
    nsl_amba.axi4_stream.frame_queue_put(root => cmd_q,
                                         data => nsl_data.bytestream.from_suv(x"4454455354"));

    -- First expect TX confirmation (F5)
    nsl_amba.axi4_stream.frame_queue_check(root => rsp_q,
                                           data => nsl_data.bytestream.from_suv(x"f5"),
                                           check_status => check_status,
                                           dt      => c_clock_period,
                                           timeout => c_clock_period*1500000,
                                           sev     => warning);
    nsl_simulation.logging.log_test_result("No parity TX confirmation", check_status, pass_count, fail_count);

    -- Then expect RX loopback data
    nsl_amba.axi4_stream.frame_queue_check(root => rsp_q,
                                           data => nsl_data.bytestream.from_suv(x"59000454455354"),
                                           check_status => check_status,
                                           dt      => c_clock_period,
                                           timeout => c_clock_period*25000000,
                                           sev     => warning);
    nsl_simulation.logging.log_test_result("Message with no parity (TEST)", check_status, pass_count, fail_count);

    -- Test 11: Configure odd parity
    -- parity: "o" = 61 6f
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1 => nsl_data.bytestream.from_suv(x"A369666C6F772D6374726C636374736670617269747961" & x"6f" & x"69626175642D726174651a0001c200"),
                                              data2 => nsl_data.bytestream.from_suv(x"F5"),
                                              check_status => check_status,
                                              dt      => c_clock_period,
                                              timeout => c_clock_period*1500000,
                                              sev     => warning);
    nsl_simulation.logging.log_test_result("Configure odd parity", check_status, pass_count, fail_count);

    -- Test 12: Verify odd parity via query
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1 => nsl_data.bytestream.from_suv(x"F6"),
                                              data2 => nsl_data.bytestream.from_suv(x"A369666C6F772D6374726C636374736670617269747961" & x"6f" & x"69626175642D726174651a0001c200"),
                                              check_status => check_status,
                                              dt      => c_clock_period,
                                              timeout => c_clock_period*1500000,
                                              sev     => warning);
    nsl_simulation.logging.log_test_result("Verify odd parity config", check_status, pass_count, fail_count);

    -- Test 13: Configure no flow control
    -- flow-ctrl: "none" = 64 6e6f6e65
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1 => nsl_data.bytestream.from_suv(x"A369666C6F772D6374726C" & x"646e6f6e65" & x"6670617269747961" & x"6e" & x"69626175642D726174651a0001c200"),
                                              data2 => nsl_data.bytestream.from_suv(x"F5"),
                                              check_status => check_status,
                                              dt      => c_clock_period,
                                              timeout => c_clock_period*1500000,
                                              sev     => warning);
    nsl_simulation.logging.log_test_result("Configure no flow control", check_status, pass_count, fail_count);

    -- Test 14: Verify no flow control via query
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1 => nsl_data.bytestream.from_suv(x"F6"),
                                              data2 => nsl_data.bytestream.from_suv(x"A369666C6F772D6374726C" & x"646e6f6e65" & x"6670617269747961" & x"6e" & x"69626175642D726174651a0001c200"),
                                              check_status => check_status,
                                              dt      => c_clock_period,
                                              timeout => c_clock_period*1500000,
                                              sev     => warning);
    nsl_simulation.logging.log_test_result("Verify no flow control config", check_status, pass_count, fail_count);

    -- Test 15: Send message with special characters (0x00, 0xff)
    -- With single FSM, F5 comes first, then RX loopback data
    nsl_amba.axi4_stream.frame_queue_put(root => cmd_q,
                                         data => nsl_data.bytestream.from_suv(x"4400ff55aa"));

    -- First expect TX confirmation (F5)
    nsl_amba.axi4_stream.frame_queue_check(root => rsp_q,
                                           data => nsl_data.bytestream.from_suv(x"f5"),
                                           check_status => check_status,
                                           dt      => c_clock_period,
                                           timeout => c_clock_period*1500000,
                                           sev     => warning);
    nsl_simulation.logging.log_test_result("Special chars TX confirmation", check_status, pass_count, fail_count);

    -- Then expect RX loopback data
    nsl_amba.axi4_stream.frame_queue_check(root => rsp_q,
                                           data => nsl_data.bytestream.from_suv(x"5900" & x"0400ff55aa"),
                                           check_status => check_status,
                                           dt      => c_clock_period,
                                           timeout => c_clock_period*25000000,
                                           sev     => warning);
    nsl_simulation.logging.log_test_result("Message with special chars", check_status, pass_count, fail_count);

    -- Test 17: Maximum size message (120 bytes = bstr_max_size_c)
    -- F5 (confirmation of message sent) comes first, then RX loopback data
    nsl_amba.axi4_stream.frame_queue_put(root => cmd_q,
                                         data => nsl_data.bytestream.from_suv(x"58784C6F72656D20697073756D20646F6C6F722073697420616D65742C20636F6E73656374657475722061646970697363696E6720656C69742E204D616563656E6173206672696E67696C6C6120616E7465206E6F6E20756C7472696369657320636F6E6775652E205175697371756520656C656966656E642E"));

    -- First expect TX confirmation (F5)
    nsl_amba.axi4_stream.frame_queue_check(root => rsp_q,
                                           data => nsl_data.bytestream.from_suv(x"f5"),
                                           check_status => check_status,
                                           dt      => c_clock_period,
                                           timeout => c_clock_period*25000000,
                                           sev     => warning);
    nsl_simulation.logging.log_test_result("Max size TX confirmation", check_status, pass_count, fail_count);

    -- Then expect RX loopback data
    nsl_amba.axi4_stream.frame_queue_check(root => rsp_q,
                                           data => nsl_data.bytestream.from_suv(x"5900784C6F72656D20697073756D20646F6C6F722073697420616D65742C20636F6E73656374657475722061646970697363696E6720656C69742E204D616563656E6173206672696E67696C6C6120616E7465206E6F6E20756C7472696369657320636F6E6775652E205175697371756520656C656966656E642E"),
                                           check_status => check_status,
                                           dt      => c_clock_period,
                                           timeout => c_clock_period*25000000,
                                           sev     => warning);
    nsl_simulation.logging.log_test_result("Maximum size message (120 bytes)", check_status, pass_count, fail_count);

    nsl_simulation.logging.log_test_suite_summary("UART CBOR TRANSACTOR TESTS", pass_count, fail_count);

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
    nsl_amba.axi4_stream.frame_queue_master(cfg => c_cfg, root => cmd_q, clock => s_clk,
                                            stream_i => s_cmd.s, stream_o => s_cmd.m, dt => c_clock_period);    
  end process;
  
  rsp_queue: process
  begin
    -- Let FSM reach IDLE and queues be initialized
    wait for 70 ns;
    nsl_simulation.logging.log(level => nsl_simulation.logging.LOG_LEVEL_INFO, message => "Going to run frame_queue_slave", color => nsl_simulation.logging.LOG_COLOR_YELLOW);
    nsl_amba.axi4_stream.frame_queue_slave(cfg => c_cfg, root => rsp_q, clock => s_clk,
                                           stream_i => s_rsp.m, stream_o => s_rsp.s, dt => c_clock_period);   
  end process;

end architecture;
