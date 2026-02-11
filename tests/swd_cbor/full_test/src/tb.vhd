library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb is
end tb;

library nsl_coresight, nsl_amba, nsl_simulation, nsl_data, nsl_event;

architecture arch of tb is
  constant clock_period : time := 10 ns;
  constant cfg_c: nsl_amba.axi4_stream.config_t
    := nsl_amba.axi4_stream.config(1, last => true);
  constant tick_divisor: unsigned(7 downto 0) := (others => '1');

  signal s_clk, s_resetn : std_ulogic;
  
  signal s_cmd        : nsl_amba.axi4_stream.bus_t;
  signal s_rsp        : nsl_amba.axi4_stream.bus_t;
  signal s_rsp_pre    : nsl_amba.axi4_stream.bus_t;

  signal s_master_swd : nsl_coresight.swd.swd_master_bus;
  signal s_slave_swd  : nsl_coresight.swd.swd_slave_bus;

  signal s_done          : std_ulogic_vector(0 to 0);

  signal tick_i_hz_s : natural := 1;
  signal tick_s : std_ulogic;
 
  shared variable cmd_q, rsp_q: nsl_amba.axi4_stream.frame_queue_root_t;
  
begin
  
  s_slave_swd.i <= nsl_coresight.swd.to_slave(s_master_swd.o);
  s_master_swd.i <= nsl_coresight.swd.to_master(s_slave_swd.o);
  
  target: block is
    constant clock_period_c : time := 20 ns;
    signal clock_s : std_ulogic;
    signal reset_n_s : std_ulogic;

    constant dp_idr_c : unsigned := x"04567e11";

    signal dapbus_gen, dapbus_memap : nsl_coresight.dapbus.dapbus_bus;
    constant axi_cfg_c : nsl_amba.axi4_mm.config_t := nsl_amba.axi4_mm.config(address_width => 32, data_bus_width => 32);
    signal axi_s : nsl_amba.axi4_mm.bus_t;
    signal ctrl, ctrl_w, stat :std_ulogic_vector(31 downto 0);
  begin
    dp: nsl_coresight.dp.swdp_sync
      generic map(
        idr => dp_idr_c
        )
      port map(
        ref_clock_i => clock_s,
        ref_reset_n_i => reset_n_s,

        swd_i => s_slave_swd.i,
        swd_o => s_slave_swd.o,

        dap_o => dapbus_gen.ms,
        dap_i => dapbus_gen.sm,

        ctrl_o => ctrl,
        stat_i => stat,
        abort_o => open
        );

    stat_update: process(ctrl)
    begin
      stat <= ctrl;
      stat(27) <= ctrl(26);
      stat(29) <= ctrl(28);
      stat(31) <= ctrl(30);
    end process;
    
    interconnect: nsl_coresight.dapbus.dapbus_interconnect
      generic map(
        access_port_count => 1
        )
      port map(
        s_i => dapbus_gen.ms,
        s_o => dapbus_gen.sm,

        m_i(0) => dapbus_memap.sm,
        m_o(0) => dapbus_memap.ms
        );

    mem_ap: nsl_coresight.ap.ap_axi4_lite
      generic map(
        rom_base => x"00000000",
        config_c => axi_cfg_c,
        idr => x"01234e11"
        )
      port map(
        clk_i => clock_s,
        reset_n_i => reset_n_s,

        dbgen_i => ctrl(28),
        spiden_i => '1',

        dap_i => dapbus_memap.ms,
        dap_o => dapbus_memap.sm,

        axi_o => axi_s.m,
        axi_i => axi_s.s
        );

    mem: nsl_amba.ram.axi4_mm_lite_ram
      generic map (
        byte_size_l2_c => 12,
        config_c => axi_cfg_c
        )
      port map (
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        axi_i => axi_s.m,
        axi_o => axi_s.s
        );

    driver_target: nsl_simulation.driver.simulation_driver
      generic map(
        clock_count => 1,
        reset_count => 1,
        done_count => s_done'length
        )
      port map(
        clock_period(0) => clock_period_c,
        reset_duration(0) => 42 ns,
        reset_n_o(0) => reset_n_s,
        clock_o(0) => clock_s,
        done_i => s_done
        );
  end block;

  tick_i_hz_s <= 10e7/to_integer(tick_divisor);
  
  dut: nsl_coresight.cbor_transactor.axi4stream_cbor_dp_transactor
    generic map(
      clock_i_hz_c   => 10e7,
     stream_config_c => cfg_c
      )
    port map(
      clock_i   =>  s_clk,
      reset_n_i => s_resetn,

      tick_i    => tick_s,
      
      cmd_i  => s_cmd.m,
      cmd_o  => s_cmd.s,

      -- rsp_o  => s_rsp_pre.m,
      -- rsp_i  => s_rsp_pre.s,

      rsp_o  => s_rsp.m,
      rsp_i  => s_rsp.s,
      
      swd_i  => s_master_swd.i,
      swd_o  => s_master_swd.o
      );

  -- rsp_pacer : nsl_amba.stream_traffic.axi4_stream_pacer
  --   generic map(
  --     config_c => cfg_c,
  --     probability_c => 0.99
  --     )
  --   port map(
  --     clock_i => s_clk,
  --     reset_n_i => s_resetn,

  --     in_i => s_rsp_pre.m,
  --     in_o => s_rsp_pre.s,

  --     out_o => s_rsp.m,
  --     out_i => s_rsp.s
  --     ); 
  
  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => s_done'length
      )
    port map(
      clock_period(0) => clock_period,
      reset_duration(0) => 42 ns,
      reset_n_o(0) => s_resetn,
      clock_o(0) => s_clk,
      done_i => s_done
      );

  tick_gen: nsl_event.tick.tick_generator_integer
    port map(
      clock_i => s_clk,
      reset_n_i => s_resetn,
      period_m1_i => tick_divisor,
      tick_o => tick_s
      );
  
  stim: process
    variable check_status : boolean := false;
    variable pass_count, fail_count : integer := 0;
    variable rx_frm : nsl_amba.axi4_stream.frame_t;  -- For receiving/discarding responses
  begin
    -- Let FSM reach IDLE
    wait for 50 ns;

    nsl_amba.axi4_stream.frame_queue_init(cmd_q);
    nsl_amba.axi4_stream.frame_queue_init(rsp_q);

    nsl_simulation.logging.log(
      level => nsl_simulation.logging.LOG_LEVEL_INFO,
      message => "======================================",
      color => nsl_simulation.logging.LOG_COLOR_CYAN
    );
    nsl_simulation.logging.log(
      level => nsl_simulation.logging.LOG_LEVEL_INFO,
      message => "SWD CBOR TRANSACTOR TEST SUITE",
      color => nsl_simulation.logging.LOG_COLOR_CYAN
    );
    nsl_simulation.logging.log(
      level => nsl_simulation.logging.LOG_LEVEL_INFO,
      message => "======================================",
      color => nsl_simulation.logging.LOG_COLOR_CYAN
    );

    -- Test 1: JTAG-to-SWD sequence (true = f5)
    -- Command: [true] = 81 f5
    -- Response: empty indefinite array (no response for protocol switch)
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1       => nsl_data.bytestream.from_suv(x"81f5"),
                                              data2       => nsl_data.bytestream.from_suv(x"9fff"),
                                              check_status => check_status,
                                              dt          => clock_period,
                                              timeout     => clock_period*2000000,
                                              sev         => warning);
    nsl_simulation.logging.log_test_result("JTAG-to-SWD sequence", check_status, pass_count, fail_count);

    wait for 50 ns;
    
    -- Test 2: Run command (50 cycles) for line reset
    -- Command: [50] = 81 18 32
    -- Response: empty (no response for run)
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1       => nsl_data.bytestream.from_suv(x"811832"),
                                              data2       => nsl_data.bytestream.from_suv(x"9fff"),
                                              check_status => check_status,
                                              dt          => clock_period,
                                              timeout     => clock_period*2000000,
                                              sev         => warning);
    nsl_simulation.logging.log_test_result("Run 50 cycles", check_status, pass_count, fail_count);

    wait for 50 ns;
    
    -- Test 3: Read DP IDR (reg0, 1 word)
    -- Command: [#6.0(1)] = 81 c0 01
    -- Response: [array(3): [indef_bstr[bstr(4 bytes IDR)], read_words=1, status=1(OK)]]
    -- DP IDR = 0x04567e11
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1       => nsl_data.bytestream.from_suv(x"81c001"),
                                              data2       => nsl_data.bytestream.from_suv(x"9f835f4404567e11ff180101ff"),
                                              check_status => check_status,
                                              dt          => clock_period,
                                              timeout     => clock_period*2000000,
                                              sev         => warning);
    nsl_simulation.logging.log_test_result("Read DP IDR (reg0)", check_status, pass_count, fail_count);

    wait for 50 ns;
    
    -- Test 4: Full SWD initialization sequence
    -- Combined: turnaround(1), run(10), write CTRL/STAT, run(8), write SELECT, run(8)
    -- 86 = array(6)
    -- c8 01 = turnaround(1)
    -- 0a = run(10)
    -- c1 44 00 00 00 50 = DP reg1 write (CTRL/STAT = 0x50000000 - enable debug power)
    -- 08 = run(8)
    -- c2 44 f0 00 00 00 = DP reg2 write (SELECT = 0x000000F0 - AP0 bank F)
    -- 08 = run(8)
    -- Responses: write response x2 = 82 18 01 01, 82 18 01 01 (written_words=1, status=OK)
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1       => nsl_data.bytestream.from_suv(x"86c8010ac1440000005008c244f000000008"),
                                              data2       => nsl_data.bytestream.from_suv(x"9f8218010182180101ff"),
                                              check_status => check_status,
                                              dt          => clock_period,
                                              timeout     => clock_period*5000000,
                                              sev         => warning);
    nsl_simulation.logging.log_test_result("SWD init (CTRL/STAT + SELECT)", check_status, pass_count, fail_count);

    wait for 50 ns;
    
    -- Test 5: Trigger AP read to load AP IDR into RDBUFF
    -- AP reads are posted - first read returns stale data, result goes to RDBUFF
    -- Command: [run(8), #6.7(1)] = 82 08 c7 01
    -- Response contains stale/undefined data - consume but don't verify
    nsl_amba.axi4_stream.frame_queue_put(root => cmd_q,
                                         data => nsl_data.bytestream.from_suv(x"8208c701"));
    -- Consume the response (stale data) without checking it
    nsl_amba.axi4_stream.frame_queue_get(root => rsp_q,
                                         frm => rx_frm,
                                         dt => clock_period,
                                         timeout => clock_period*5000000,
                                         sev => warning);
    check_status := true;  -- Consider pass since we just need to trigger the AP read
    nsl_simulation.logging.log_test_result("AP read trigger (stale response consumed)", check_status, pass_count, fail_count);

    wait for 50 ns;
    
    -- Test 6: Read DP CTRL/STAT (reg1) - verify debug power enabled
    -- Command: [#6.1(1)] = 81 c1 01
    -- Response: [array(3): [indef_bstr[bstr(4 bytes)], read_words=1, status=1(OK)]]
    -- Note: Returns 0xF0000000 (ctrl bits with ack bits set) as 00 00 00 f0 (LE)
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1       => nsl_data.bytestream.from_suv(x"81c101"),
                                              data2       => nsl_data.bytestream.from_suv(x"9f835f44f0000000ff180101ff"),
                                              check_status => check_status,
                                              dt          => clock_period,
                                              timeout     => clock_period*5000000,
                                              sev         => warning);
    nsl_simulation.logging.log_test_result("Read DP CTRL/STAT (reg1)", check_status, pass_count, fail_count);
    
    wait for 50 ns;
    
    -- Test 7: Read DP RDBUFF (reg3) - returns last AP read result (AP IDR)
    -- Command: [#6.3(1)] = 81 c3 01
    -- Response: [array(3): [indef_bstr[bstr(4 bytes)], read_words=1, status=1(OK)]]
    -- AP IDR = 0x01234e11 returned as: 01 23 4e 11
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1       => nsl_data.bytestream.from_suv(x"81c301"),
                                              data2       => nsl_data.bytestream.from_suv(x"9f835f4401234e11ff180101ff"),
                                              check_status => check_status,
                                              dt          => clock_period,
                                              timeout     => clock_period*5000000,
                                              sev         => warning);
    nsl_simulation.logging.log_test_result("Read DP RDBUFF (reg3)", check_status, pass_count, fail_count);
    
    wait for 50 ns;
    
    -- Test 8: Bitbang custom sequence (8 bytes of 0xFF = 64 high clocks for line reset)
    -- Command: [#6.9(bstr(8 bytes))] = 81 c9 48 ff ff ff ff ff ff ff ff
    -- Response: empty (no response for bitbang)
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1       => nsl_data.bytestream.from_suv(x"81c948ffffffffffffffff"),
                                              data2       => nsl_data.bytestream.from_suv(x"9fff"),
                                              check_status => check_status,
                                              dt          => clock_period,
                                              timeout     => clock_period*2000000,
                                              sev         => warning);
    nsl_simulation.logging.log_test_result("Bitbang line reset", check_status, pass_count, fail_count);

    wait for 50 ns;
    
    -- Test 9: Set turnaround to 2 cycles (default)
    -- Command: [#6.8(2)] = 81 c8 02
    -- Response: empty (sticky setting)
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1       => nsl_data.bytestream.from_suv(x"81c802"),
                                              data2       => nsl_data.bytestream.from_suv(x"9fff"),
                                              check_status => check_status,
                                              dt          => clock_period,
                                              timeout     => clock_period*2000000,
                                              sev         => warning);
    nsl_simulation.logging.log_test_result("Set turnaround (2 cycles)", check_status, pass_count, fail_count);

    wait for 50 ns;

    -- The bitbang tests can be checked in the waveform, here I only check that the response follows the spec
    
    -- Test 10: Set turnaround to 3 cycles
    -- Command: [#6.8(3)] = 81 c8 03
    -- Response: empty (sticky setting)
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1       => nsl_data.bytestream.from_suv(x"81c803"),
                                              data2       => nsl_data.bytestream.from_suv(x"9fff"),
                                              check_status => check_status,
                                              dt          => clock_period,
                                              timeout     => clock_period*2000000,
                                              sev         => warning);
    nsl_simulation.logging.log_test_result("Set turnaround (3 cycles)", check_status, pass_count, fail_count);

    wait for 50 ns;
    
    -- Test 11: Short bitbang (1 byte = 8 bits with alternating pattern)
    -- Command: [#6.9(bstr(1 byte))] = 81 c9 41 aa
    -- Response: empty (no response for bitbang)
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1       => nsl_data.bytestream.from_suv(x"81c941aa"),
                                              data2       => nsl_data.bytestream.from_suv(x"9fff"),
                                              check_status => check_status,
                                              dt          => clock_period,
                                              timeout     => clock_period*2000000,
                                              sev         => warning);
    nsl_simulation.logging.log_test_result("Bitbang short (1 byte)", check_status, pass_count, fail_count);

    wait for 50 ns;
    
    -- Test 12: Bitbang with alternating pattern (4 bytes: AA 55 AA 55)
    -- Command: [#6.9(bstr(4 bytes))] = 81 c9 44 aa 55 aa 55
    -- Response: empty (no response for bitbang)
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1       => nsl_data.bytestream.from_suv(x"81c944aa55aa55"),
                                              data2       => nsl_data.bytestream.from_suv(x"9fff"),
                                              check_status => check_status,
                                              dt          => clock_period,
                                              timeout     => clock_period*2000000,
                                              sev         => warning);
    nsl_simulation.logging.log_test_result("Bitbang alternating pattern (4 bytes)", check_status, pass_count, fail_count);

    wait for 50 ns;
    
    -- Test 13: Bitbang combined with run in same array
    -- Command: [run(8), #6.9(bstr(2 bytes)), run(8)] = 83 08 c9 42 12 34 08
    -- Response: empty (no response for run or bitbang)
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1       => nsl_data.bytestream.from_suv(x"8308c942123408"),
                                              data2       => nsl_data.bytestream.from_suv(x"9fff"),
                                              check_status => check_status,
                                              dt          => clock_period,
                                              timeout     => clock_period*2000000,
                                              sev         => warning);
    nsl_simulation.logging.log_test_result("Bitbang combined with run commands", check_status, pass_count, fail_count);

    wait for 50 ns;
    
    -- Test 14: Longer bitbang sequence (16 bytes for a complete JTAG-to-SWD + line reset)
    -- This sends: 0xFF x 7 (56 high bits) + 0x9E (JTAG-to-SWD) + 0xFF x 7 (56 high bits) + 0x00 (idle)
    -- Command: [#6.9(bstr(16 bytes))] = 81 c9 50 + 16 bytes
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1       => nsl_data.bytestream.from_suv(x"81c950ffffffffffffff9effffffffffffff00"),
                                              data2       => nsl_data.bytestream.from_suv(x"9fff"),
                                              check_status => check_status,
                                              dt          => clock_period,
                                              timeout     => clock_period*5000000,
                                              sev         => warning);
    nsl_simulation.logging.log_test_result("Bitbang long sequence (16 bytes)", check_status, pass_count, fail_count);

    wait for 50 ns;
    
    -- Test 15: Multi-word write (8 bytes = 2 words)
    -- Command: [turnaround(1), run(8), #6.1(bstr(8 bytes))]
    -- Response: [2, 1] = 2 words written, status OK
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1       => nsl_data.bytestream.from_suv(x"83c80108c1480000005000000050"),
                                              data2       => nsl_data.bytestream.from_suv(x"9f82180201ff"),
                                              check_status => check_status,
                                              dt          => clock_period,
                                              timeout     => clock_period*5000000,
                                              sev         => warning);
    nsl_simulation.logging.log_test_result("Multi-word write (2 words)", check_status, pass_count, fail_count);
   
    wait for 50 ns;
    
    -- Test 16: Multi-word read (8 bytes = 2 words)
    -- Command: [turnaround(1), run(8), #6.1(2)] = read DP reg1 (CTRL/STAT) 2 words
    -- Response: array(3)[indef_bstr[bstr(4)+data1, bstr(4)+data2], break, word_count=2, status=OK]
    -- SWD stub returns f0 00 00 00 for CTRL/STAT
    nsl_amba.axi4_stream.frame_queue_check_io(root_master => cmd_q,
                                              root_slave  => rsp_q,
                                              data1       => nsl_data.bytestream.from_suv(x"83c80108c102"),
                                              data2       => nsl_data.bytestream.from_suv(x"9f835f44f000000044f0000000ff180201ff"),
                                              check_status => check_status,
                                              dt          => clock_period,
                                              timeout     => clock_period*5000000,
                                              sev         => warning);
    nsl_simulation.logging.log_test_result("Multi-word read (2 words)", check_status, pass_count, fail_count);
        
    wait for 1 ms;

    nsl_simulation.logging.log_test_suite_summary("SWD CBOR TRANSACTOR TESTS", pass_count, fail_count);

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
                                            stream_i => s_cmd.s, stream_o => s_cmd.m, dt => clock_period); --, timeout => 200000 ms);    
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
