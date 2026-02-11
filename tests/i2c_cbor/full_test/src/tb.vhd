library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb is
end tb;

library nsl_i2c, nsl_amba, nsl_simulation, nsl_data;


architecture arch of tb is
  constant clock_period : time := 10 ns;
  constant cfg_c: nsl_amba.axi4_stream.config_t
    := nsl_amba.axi4_stream.config(1, last => true);

  signal s_cmd           : nsl_amba.axi4_stream.bus_t;
  signal s_rsp           : nsl_amba.axi4_stream.bus_t;
  signal s_rsp_pre       : nsl_amba.axi4_stream.bus_t;
  
  signal s_i2c           : nsl_i2c.i2c.i2c_i;
  signal s_i2c_slave1, s_i2c_slave2, s_i2c_slave3, s_i2c_slave4, s_i2c_slave5, s_i2c_master : nsl_i2c.i2c.i2c_o;

  signal s_clk, s_resetn : std_ulogic;
  signal s_done : std_ulogic_vector(0 to 0);

  constant MAX_COUNT     : natural := 400; -- 4 us
  signal counter         : natural range 0 to MAX_COUNT := 0;
  signal s_enable_slave4 : std_ulogic;
  signal s_resetn_slave4 : std_ulogic;
  
  shared variable cmd_q, rsp_q: nsl_amba.axi4_stream.frame_queue_root_t;
  
  -- Test control signals
  signal test_timeout : boolean := false;
  signal test_complete : boolean := false;
    
begin

  resolver: nsl_i2c.i2c.i2c_resolver
    generic map(
      port_count => 6
      )
    port map(
      bus_i(0) => s_i2c_slave1,
      bus_i(1) => s_i2c_slave2,
      bus_i(2) => s_i2c_slave3,
      bus_i(3) => s_i2c_slave4,
      bus_i(4) => s_i2c_slave5,
      bus_i(5) => s_i2c_master,
      bus_o => s_i2c
      );

  
  i2c_slave: nsl_i2c.clocked.clocked_slave
    generic map(
      clock_freq_c => 10e7
    )
    port map(
      reset_n_i => s_resetn,
      clock_i   => s_clk,

      address_i => "1010000", -- 0x50

      i2c_i    => s_i2c,
      i2c_o    => s_i2c_slave1,

      start_o  => open,
      stop_o   => open,
      selected_o => open,
      
      r_data_i  => X"AA",
      r_ready_o => open,
      r_valid_i => '1',

      w_data_o  => open,
      w_valid_o => open,
      w_ready_i => '1'
    );

  i2c_slave_10b: entity work.clocked_slave_10bit
    generic map(
      clock_freq_c => 10e7
    )
    port map(
      reset_n_i => s_resetn,
      clock_i   => s_clk,

      address_i => "0100010000", -- 0x110 (10-bit address)

      i2c_i    => s_i2c,
      i2c_o    => s_i2c_slave5,

      start_o  => open,
      stop_o   => open,
      selected_o => open,

      r_data_i  => X"CC",  -- Different response than 7-bit slave
      r_ready_o => open,
      r_valid_i => '1',

      w_data_o  => open,
      w_valid_o => open,
      w_ready_i => '1'
    );

  i2c_mem: nsl_i2c.clocked.clocked_memory
    generic map(
      address => "1000000", -- 0x40
      addr_width => 16
      )
    port map(
      clock_i  => s_clk,
      reset_n_i => s_resetn,

      i2c_i => s_i2c,
      i2c_o => s_i2c_slave2
      );  

  
  i2c_slave_nack: entity work.clocked_slave_nack
    generic map(
      clock_freq_c => 10e7
    )
    port map(
      reset_n_i => s_resetn,
      clock_i   => s_clk,

      address_i => "0110000", -- 0x30

      i2c_i    => s_i2c,
      i2c_o    => s_i2c_slave3,

      start_o  => open,
      stop_o   => open,
      selected_o => open,
      
      r_data_i  => X"AA",
      r_ready_o => open,
      r_valid_i => '1',

      w_data_o  => open,
      w_valid_o => open,
      w_ready_i => '1'
    );

  
  i2c_slave_delayed: nsl_i2c.clocked.clocked_slave
    generic map(
      clock_freq_c => 10e7
    )
    port map(
      reset_n_i => s_resetn_slave4,
      clock_i   => s_clk,

      address_i => "0100000", -- 0x20

      i2c_i    => s_i2c,
      i2c_o    => s_i2c_slave4,

      start_o  => open,
      stop_o   => open,
      selected_o => open,
      
      r_data_i  => X"BB",
      r_ready_o => open,
      r_valid_i => '1',

      w_data_o  => open,
      w_valid_o => open,
      w_ready_i => '1'
    );

  
  dut: nsl_i2c.cbor_transactor.controller
    generic map(
      clock_i_hz_c => 10e7,
      axi_s_cfg_c  => cfg_c
      )
    port map(
      clock_i  =>  s_clk,
      reset_n_i => s_resetn,
      
      cmd_i => s_cmd.m,
      cmd_o => s_cmd.s,

      rsp_o => s_rsp_pre.m,
      rsp_i => s_rsp_pre.s,
      
      i2c_i => s_i2c,
      i2c_o => s_i2c_master
      );

  rsp_pacer : nsl_amba.stream_traffic.axi4_stream_pacer
    generic map(
      config_c => cfg_c,
      probability_c => 0.1
      )
  port map(
    clock_i => s_clk,
    reset_n_i => s_resetn,

    in_i => s_rsp_pre.m,
    in_o => s_rsp_pre.s,

    out_o => s_rsp.m,
    out_i => s_rsp.s
    ); 
  
  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => 1
      )
    port map(
      clock_period(0) => clock_period,
      reset_duration(0) => 3*clock_period,
      reset_n_o(0) => s_resetn,
      clock_o(0) => s_clk,
      done_i => s_done
      );
  
  -- Keep slave4 in reset state until s_enable_slave4 is set to '1'
  -- Then wait 4 us and release the reset
  process(s_clk)
  begin
    if rising_edge(s_clk) then
      s_resetn_slave4 <= '0';
      if s_enable_slave4 = '0' then
        counter         <= 0;
      elsif counter < MAX_COUNT then -- 4 us
        counter  <= counter + 1;
      else
        s_resetn_slave4 <= '1'; -- release reset
      end if;
    end if;
  end process;
  
  -- Global timeout watchdog
  timeout_watchdog: process
  begin
    wait for 100 ms;  -- Global timeout for entire test suite
    if not test_complete then
      report "======================================" severity error;
      report "GLOBAL TIMEOUT - Test suite did not complete in time" severity error;
      report "======================================" severity error;
      test_timeout <= true;
      nsl_simulation.control.terminate(2);  -- Exit with timeout error code
    end if;
    wait;
  end process;
  
  stim: process
    variable check_status : boolean := false;
    variable pass_count, fail_count : integer := 0;
    
  begin
    -- Let FSM reach IDLE
    wait for 50 ns;

    s_enable_slave4 <= '0';
    
    nsl_amba.axi4_stream.frame_queue_init(cmd_q);
    nsl_amba.axi4_stream.frame_queue_init(rsp_q);

    nsl_simulation.logging.log_test_suite_start("I2C CBOR TRANSACTOR TEST SUITE");

    -- Test 0: Write to clocked slave
    nsl_amba.axi4_stream.frame_queue_check_io(
      root_master => cmd_q,
      root_slave  => rsp_q,
      data1       => nsl_data.bytestream.from_suv(x"8182185043123456"),
      data2       => nsl_data.bytestream.from_suv(x"9ff6ff"),
      check_status => check_status,
      dt          => clock_period,
      timeout     => clock_period*200000,
      sev         => warning
    );
    nsl_simulation.logging.log_test_result("Write to clocked slave", check_status, pass_count, fail_count);
    
    -- Test 1: Read from clocked slave
    nsl_amba.axi4_stream.frame_queue_check_io(
      root_master => cmd_q,
      root_slave  => rsp_q,
      data1       => nsl_data.bytestream.from_suv(x"8282185002f6"),
      data2       => nsl_data.bytestream.from_suv(x"9f590002aaaaff"),
      check_status => check_status,
      dt          => clock_period,
      timeout     => clock_period*200000,
      sev         => warning
    );
    nsl_simulation.logging.log_test_result("Read from clocked slave", check_status, pass_count, fail_count);
    
    -- Test 2: Write to memory
    nsl_amba.axi4_stream.frame_queue_check_io(
      root_master => cmd_q,
      root_slave  => rsp_q,
      data1       => nsl_data.bytestream.from_suv(x"828218404400001234f6"),
      data2       => nsl_data.bytestream.from_suv(x"9ff6ff"),
      check_status => check_status,
      dt          => clock_period,
      timeout     => clock_period*200000,
      sev         => warning
    );
    nsl_simulation.logging.log_test_result("Write to memory", check_status, pass_count, fail_count);
    
    -- Test 3: Read from memory (2x i2c read and write with restart)
    nsl_amba.axi4_stream.frame_queue_check_io(
      root_master => cmd_q,
      root_slave  => rsp_q,
      data1       => nsl_data.bytestream.from_suv(x"8682184042000082184001f682184042000182184001f6"),
      data2       => nsl_data.bytestream.from_suv(x"9ff659000112f659000134ff"),
      check_status => check_status,
      dt          => clock_period,
      timeout     => clock_period*200000,
      sev         => warning
    );
    nsl_simulation.logging.log_test_result("Read from memory (2x i2c read/write with restart)", check_status, pass_count, fail_count);
    
    -- Test 4: Read 3 bytes from memory address 0x00
    nsl_amba.axi4_stream.frame_queue_check_io(
      root_master => cmd_q,
      root_slave  => rsp_q,
      data1       => nsl_data.bytestream.from_suv(x"8382184042000082184003f6"),
      data2       => nsl_data.bytestream.from_suv(x"9ff65900031234ffff"),
      check_status => check_status,
      dt          => clock_period,
      timeout     => clock_period*200000,
      sev         => warning
    );
    nsl_simulation.logging.log_test_result("Read 3 bytes from memory address 0x00", check_status, pass_count, fail_count);
    
    -- Test 5: Access to non-existent address
    nsl_amba.axi4_stream.frame_queue_check_io(
      root_master => cmd_q,
      root_slave  => rsp_q,
      data1       => nsl_data.bytestream.from_suv(x"828218604112f6"),
      data2       => nsl_data.bytestream.from_suv(x"9ff4ff"),
      check_status => check_status,
      dt          => clock_period,
      timeout     => clock_period*200000,
      sev         => warning
    );
    nsl_simulation.logging.log_test_result("Access to non-existent address (expect NACK)", check_status, pass_count, fail_count);
    
    -- Test 6: NACK for data bytes
    nsl_amba.axi4_stream.frame_queue_check_io(
      root_master => cmd_q,
      root_slave  => rsp_q,
      data1       => nsl_data.bytestream.from_suv(x"82821830421234f6"),
      data2       => nsl_data.bytestream.from_suv(x"9fc2190000ff"),
      check_status => check_status,
      dt          => clock_period,
      timeout     => clock_period*200000,
      sev         => warning
    );
    nsl_simulation.logging.log_test_result("NACK for data bytes", check_status, pass_count, fail_count);

    -- Test 7: Poll-read for non-existent slave
    nsl_amba.axi4_stream.frame_queue_check_io(
      root_master => cmd_q,
      root_slave  => rsp_q,
      data1       => nsl_data.bytestream.from_suv(x"82c1830a187002f6"),
      data2       => nsl_data.bytestream.from_suv(x"9ff4ff"),
      check_status => check_status,
      dt          => clock_period,
      timeout     => clock_period*200000,
      sev         => warning
    );
    nsl_simulation.logging.log_test_result("Poll-read for non-existent slave", check_status, pass_count, fail_count);

    -- Test 8: Poll-read for delayed slave
    s_enable_slave4 <= '1';
    nsl_amba.axi4_stream.frame_queue_check_io(
      root_master => cmd_q,
      root_slave  => rsp_q,
      data1       => nsl_data.bytestream.from_suv(x"82c1831864182001f6"),
      data2       => nsl_data.bytestream.from_suv(x"9f590001bbff"),
      check_status => check_status,
      dt          => clock_period,
      timeout     => clock_period*200000,
      sev         => warning
    );
    nsl_simulation.logging.log_test_result("Poll-read for slave enabled after 4us (timeout 100us)", check_status, pass_count, fail_count);

    -- Test 9: Simple read from non-existent address (not poll-read, expect immediate NACK)
    nsl_amba.axi4_stream.frame_queue_check_io(
      root_master => cmd_q,
      root_slave  => rsp_q,
      data1       => nsl_data.bytestream.from_suv(x"8282186002f6"),
      data2       => nsl_data.bytestream.from_suv(x"9ff4ff"),
      check_status => check_status,
      dt          => clock_period,
      timeout     => clock_period*200000,
      sev         => warning
    );
    nsl_simulation.logging.log_test_result("Read from non-existent address (expect NACK)", check_status, pass_count, fail_count);

    -- Test 10: Write followed by read with explicit stop between
    nsl_amba.axi4_stream.frame_queue_check_io(
      root_master => cmd_q,
      root_slave  => rsp_q,
      data1       => nsl_data.bytestream.from_suv(x"8482185041aaf682185001f6"),
      data2       => nsl_data.bytestream.from_suv(x"9ff6590001aaff"),
      check_status => check_status,
      dt          => clock_period,
      timeout     => clock_period*200000,
      sev         => warning
    );
    nsl_simulation.logging.log_test_result("Write followed by read with stop between", check_status, pass_count, fail_count);

    -- Test 11: Write to one slave, then write to different slave without stop (repeated start)
    nsl_amba.axi4_stream.frame_queue_check_io(
      root_master => cmd_q,
      root_slave  => rsp_q,
      data1       => nsl_data.bytestream.from_suv(x"83821850411182184044001055aaf6"),
      data2       => nsl_data.bytestream.from_suv(x"9ff6f6ff"),
      check_status => check_status,
      dt          => clock_period,
      timeout     => clock_period*200000,
      sev         => warning
    );
    nsl_simulation.logging.log_test_result("Repeated start: Write to addr 0x50, then 0x40 without stop", check_status, pass_count, fail_count);

    -- Test 12: Write followed by repeated start read (no stop between)
    nsl_amba.axi4_stream.frame_queue_check_io(
      root_master => cmd_q,
      root_slave  => rsp_q,
      data1       => nsl_data.bytestream.from_suv(x"8382185041dd82185002f6"),
      data2       => nsl_data.bytestream.from_suv(x"9ff6590002aaaaff"),
      check_status => check_status,
      dt          => clock_period,
      timeout     => clock_period*200000,
      sev         => warning
    );
    nsl_simulation.logging.log_test_result("Write followed by repeated start read (no stop)", check_status, pass_count, fail_count);

    -- Test 13: Multiple writes to different slaves in sequence with stops
    -- Commands: [write 0x50 h'0a', stop, write 0x40 h'001055aa', stop, write 0x50 h'fe', stop]
    nsl_amba.axi4_stream.frame_queue_check_io(
      root_master => cmd_q,
      root_slave  => rsp_q,
      data1       => nsl_data.bytestream.from_suv(x"86821850410af682184044001055aaf682185041fef6"),
      data2       => nsl_data.bytestream.from_suv(x"9ff6f6f6ff"),
      check_status => check_status,
      dt          => clock_period,
      timeout     => clock_period*200000,
      sev         => warning
    );
    nsl_simulation.logging.log_test_result("Multiple writes to different slaves with stops", check_status, pass_count, fail_count);

    -- Test 14: Medium length byte string write (6 bytes)
    -- Command: array(2) = [write [0x50, bstr(6)], stop]
    nsl_amba.axi4_stream.frame_queue_check_io(
      root_master => cmd_q,
      root_slave  => rsp_q,
      data1       => nsl_data.bytestream.from_suv(x"8282185046000102030405f6"),
      data2       => nsl_data.bytestream.from_suv(x"9ff6ff"),
      check_status => check_status,
      dt          => clock_period,
      timeout     => clock_period*200000,
      sev         => warning
    );
    nsl_simulation.logging.log_test_result("Medium length byte string write (6 bytes)", check_status, pass_count, fail_count);

    -- Test 15: Back-to-back writes (3 writes without stops, then final stop)
    -- Command: array(4) = [write, write, write, stop]
    nsl_amba.axi4_stream.frame_queue_check_io(
      root_master => cmd_q,
      root_slave  => rsp_q,
      data1       => nsl_data.bytestream.from_suv(x"8482185041aa82185041bb82185041ccf6"),
      data2       => nsl_data.bytestream.from_suv(x"9ff6f6f6ff"),
      check_status => check_status,
      dt          => clock_period,
      timeout     => clock_period*200000,
      sev         => warning
    );
    nsl_simulation.logging.log_test_result("Back-to-back writes (3 writes, 1 stop)", check_status, pass_count, fail_count);

    -- Test 16: Medium read operation (4 bytes, slave returns 0xAA)
    -- Command: array(2) = [read [0x50, 4], stop]
    nsl_amba.axi4_stream.frame_queue_check_io(
      root_master => cmd_q,
      root_slave  => rsp_q,
      data1       => nsl_data.bytestream.from_suv(x"8282185004f6"),
      data2       => nsl_data.bytestream.from_suv(x"9f590004aaaaaaaaff"),
      check_status => check_status,
      dt          => clock_period,
      timeout     => clock_period*200000,
      sev         => warning
    );
    nsl_simulation.logging.log_test_result("Medium read operation (4 bytes)", check_status, pass_count, fail_count);

    -- Test 17: 10-bit address write (slave at 0x110)
    -- Command: [[0x110, h'12'], null]
    nsl_amba.axi4_stream.frame_queue_check_io(
      root_master => cmd_q,
      root_slave  => rsp_q,
      data1       => nsl_data.bytestream.from_suv(x"82821901104112f6"),
      data2       => nsl_data.bytestream.from_suv(x"9ff6ff"),
      check_status => check_status,
      dt          => clock_period,
      timeout     => clock_period*200000,
      sev         => warning
    );
    nsl_simulation.logging.log_test_result("10-bit address write (0x110)", check_status, pass_count, fail_count);

    -- Test 18: 10-bit address read (slave at 0x110, returns 0xCC)
    -- Command: [[0x110, 2], null]
    nsl_amba.axi4_stream.frame_queue_check_io(
      root_master => cmd_q,
      root_slave  => rsp_q,
      data1       => nsl_data.bytestream.from_suv(x"828219011002f6"),
      data2       => nsl_data.bytestream.from_suv(x"9f590002ccccff"),
      check_status => check_status,
      dt          => clock_period,
      timeout     => clock_period*200000,
      sev         => warning
    );
    nsl_simulation.logging.log_test_result("10-bit address read (0x110)", check_status, pass_count, fail_count);

    -- Test 19: 10-bit address at boundary (0x80 = first 10-bit address)
    -- Command: [[0x80, h'ab'], null]
    nsl_amba.axi4_stream.frame_queue_check_io(
      root_master => cmd_q,
      root_slave  => rsp_q,
      data1       => nsl_data.bytestream.from_suv(x"82821880" & x"41ab" & x"f6"),
      data2       => nsl_data.bytestream.from_suv(x"9ff4ff"),
      check_status => check_status,
      dt          => clock_period,
      timeout     => clock_period*200000,
      sev         => warning
    );
    nsl_simulation.logging.log_test_result("10-bit address boundary (0x80, expect NACK)", check_status, pass_count, fail_count);

    -- Test 20: Maximum 10-bit address (0x3FF)
    -- Command: [[0x3FF, 1], null]
    nsl_amba.axi4_stream.frame_queue_check_io(
      root_master => cmd_q,
      root_slave  => rsp_q,
      data1       => nsl_data.bytestream.from_suv(x"828219" & x"03FF" & x"01f6"),
      data2       => nsl_data.bytestream.from_suv(x"9ff4ff"),
      check_status => check_status,
      dt          => clock_period,
      timeout     => clock_period*200000,
      sev         => warning
    );
    nsl_simulation.logging.log_test_result("10-bit address max (0x3FF, expect NACK)", check_status, pass_count, fail_count);

    wait for 1000 ns;

    nsl_simulation.logging.log_test_suite_summary("I2C CBOR TRANSACTOR TESTS", pass_count, fail_count);

    test_complete <= true;

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
    nsl_simulation.logging.log(level => nsl_simulation.logging.LOG_LEVEL_INFO,
                               message => "Going to run frame_queue_master", 
                               color => nsl_simulation.logging.LOG_COLOR_MAGENTA);
    nsl_amba.axi4_stream.frame_queue_master(cfg => cfg_c, root => cmd_q, clock => s_clk,
                                            stream_i => s_cmd.s, stream_o => s_cmd.m, dt => clock_period);
  end process;
  
  rsp_queue: process
  begin
    -- Let FSM reach IDLE and queues be initialized
    wait for 70 ns;
    nsl_simulation.logging.log(level => nsl_simulation.logging.LOG_LEVEL_INFO,
                               message => "Going to run frame_queue_slave", 
                               color => nsl_simulation.logging.LOG_COLOR_YELLOW);
    nsl_amba.axi4_stream.frame_queue_slave(cfg => cfg_c, root => rsp_q, clock => s_clk,
                                           stream_i => s_rsp.m, stream_o => s_rsp.s, dt => clock_period);   
  end process;
end architecture;
