library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb is
end tb;

library nsl_clocking, nsl_bnoc, nsl_coresight,
  nsl_simulation, nsl_data, nsl_axi, nsl_segger, nsl_math;
use nsl_coresight.testing.all;
use nsl_bnoc.testing.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.prbs.all;
use nsl_data.text.all;
use nsl_simulation.logging.all;
use nsl_simulation.assertions.all;
use nsl_coresight.swd.all;
use nsl_segger.rtt.all;
use nsl_segger.testing.all;
use nsl_math.arith.all;

architecture arch of tb is

  constant dut_clock_period_c : time := 20 ns;
  constant ate_clock_period_c : time := 10 ns;
  
  signal ate_clock_s : std_ulogic;
  signal ate_reset_n_s : std_ulogic;
  signal dut_clock_s : std_ulogic;
  signal dut_reset_n_s : std_ulogic;

  signal done_s : std_ulogic_vector(0 to 2);

  type framed_io is
  record
    cmd, rsp: nsl_bnoc.framed.framed_bus_t;
  end record;

  signal dp_s, memap_s, memap_rtt_s, memap_ate_s : framed_io;
  signal master_swd_s : nsl_coresight.swd.swd_master_bus;

  signal dp_ready_s : std_ulogic;

  constant dp_idr_c : unsigned := x"04567e11";
  constant rtt_control_address_c : unsigned(31 downto 0) := x"00000c80";
  constant rtt_channel_address_c : unsigned(31 downto 0) := x"00000c98";
  constant rtt_buffer_address_c : unsigned(31 downto 0) := x"00000100";
  constant rtt_buffer_length_c : unsigned(31 downto 0) := x"00000008";
  constant zero32_c : unsigned(31 downto 0) := x"00000000";
  constant rtt_interval_c : unsigned := to_unsigned_auto(32);
  
begin

  ate: block is
    constant cpol_c: std_ulogic := '0';
    constant cpha_c: std_ulogic := '0';

    shared variable ate_rsp_v, ate_cmd_v: framed_queue_root;
  begin

--    snooper_cmd: process is
--    begin
--      nsl_bnoc.testing.framed_snooper("ate cmd", memap_ate_s.cmd, ate_clock_s, 65536, ate_clock_period_c);
--    end process;
--
--    snooper_rsp: process is
--    begin
--      nsl_bnoc.testing.framed_snooper("ate rsp", memap_ate_s.rsp, ate_clock_s, 65536, ate_clock_period_c);
--    end process;

    ate_stim: process is
      variable dropped: byte_stream;
      variable state: prbs_state(0 to 30) := (others => '1');
      variable payload: byte_string(0 to 15);
    begin
      done_s(0) <= '0';
      dp_ready_s <= '0';

      wait for 100 ns;

      memap_dp_swd_init("Init", ate_cmd_v, ate_rsp_v, dp_idr_c);
      memap_param_set("Params", ate_cmd_v, ate_rsp_v, x"800000", 10);

      memap_write("ram init", ate_cmd_v, ate_rsp_v,
                  rtt_control_address_c,
                  (0 to 127 => to_byte(0)));
      memap_write("ram init", ate_cmd_v, ate_rsp_v,
                  rtt_buffer_address_c,
                  (0 to (to_integer(rtt_buffer_length_c)-1) => to_byte(0)));

      dp_ready_s <= '1';

      memap_write("Channel setup", ate_cmd_v, ate_rsp_v,
                  rtt_channel_address_c,
                  to_le(zero32_c)
                  & to_le(rtt_buffer_address_c)
                  & to_le(rtt_buffer_length_c)
                  & to_le(zero32_c)
                  & to_le(zero32_c)
                  & to_le(zero32_c));

      memap_write("Control setup", ate_cmd_v, ate_rsp_v,
                  rtt_control_address_c + rtt_control_up_count_offset_c,
                  from_hex("01000000"
                  & "00000000"));

      memap_write("Signature", ate_cmd_v, ate_rsp_v,
                  rtt_control_address_c,
                  to_01(rtt_control_signature_c));
      
      wait for 3000 ns;

      for loops in 0 to 7
      loop
        for size in 1 to 16
        loop
          prbs_next(prbs31, state, payload(0 to size-1));

          log_info("l" & to_string(loops) & "s" & to_string(size) & " < " & to_string(payload(0 to size-1)));

          memap_rtt_channel_write("l" & to_string(loops) & "s" & to_string(size),
                                  ate_cmd_v, ate_rsp_v,
                                  rtt_channel_address_c,
                                  payload(0 to size-1));
        end loop;
      end loop;

      done_s(0) <= '1';
      wait;
    end process;

    memap_ate_s_rsp_reader: process is
      variable data: byte_stream;
    begin
      framed_queue_init(ate_rsp_v);

      while true
      loop
        framed_get(memap_ate_s.rsp.req, memap_ate_s.rsp.ack, ate_clock_s, data);
        framed_queue_put(ate_rsp_v, data.all);
        deallocate(data);
      end loop;
    end process;

    memap_ate_s_cmd_writer: process is
      variable data: byte_stream;
    begin
      framed_queue_init(ate_cmd_v);

      while true
      loop
        framed_wait(memap_ate_s.cmd.req, memap_ate_s.cmd.ack, ate_clock_s, 1);
        framed_queue_get(ate_cmd_v, data);
        framed_put(memap_ate_s.cmd.req, memap_ate_s.cmd.ack, ate_clock_s, data.all);
        deallocate(data);
      end loop;
    end process;
  end block;
  
  rtt: block is
    signal up_pipe_s : nsl_bnoc.pipe.pipe_bus_t;
    signal rtt_enable_s, rtt_busy_s, rtt_error_s : std_ulogic;
  begin    

--    snooper_cmd: process is
--    begin
--      nsl_bnoc.testing.framed_snooper("rtt cmd", memap_rtt_s.cmd, ate_clock_s, 65536, ate_clock_period_c);
--    end process;
--
--    snooper_rsp: process is
--    begin
--      nsl_bnoc.testing.framed_snooper("rtt rsp", memap_rtt_s.rsp, ate_clock_s, 65536, ate_clock_period_c);
--    end process;

    rtt_up: nsl_segger.rtt.rtt_up_pipe
      port map(
        reset_n_i => ate_reset_n_s,
        clock_i => ate_clock_s,

        enable_i => rtt_enable_s,
        busy_o => rtt_busy_s,
        error_o => rtt_error_s,

        control_address_i => rtt_control_address_c(31 downto 2),
        channel_address_i => rtt_channel_address_c(31 downto 2),

        interval_i => rtt_interval_c,
        
        data_o => up_pipe_s.req,
        data_i => up_pipe_s.ack,

        memap_cmd_o => memap_rtt_s.cmd.req,
        memap_cmd_i => memap_rtt_s.cmd.ack,
        memap_rsp_i => memap_rtt_s.rsp.req,
        memap_rsp_o => memap_rtt_s.rsp.ack
        );

    pipe_dumper: process is
      variable state: prbs_state(0 to 30) := (others => '1');
      variable reference, data: byte_string(0 to 15);
    begin
      done_s(2) <= '0';
      up_pipe_s.ack.ready <= '0';
      wait for 10 us;

      for loops in 0 to 7
      loop
        for size in 1 to 16
        loop
          prbs_next(prbs31, state, reference(0 to size-1));
          pipe_read(up_pipe_s.req, up_pipe_s.ack, ate_clock_s, data(0 to size-1));

          log_info("l" & to_string(loops) & "s" & to_string(size) & " > " & to_string(data(0 to size-1)));

          assert_equal("l" & to_string(loops) & "s" & to_string(size),
                       reference(0 to size-1), data(0 to size-1),
                       failure);
        end loop;
      end loop;

      done_s(2) <= '1';
      wait;
    end process;

    rtt_control: process is

    begin
      done_s(1) <= '0';
      rtt_enable_s <= '0';
      
      wait for 1 ns;

      wait until dp_ready_s = '1';
      rtt_enable_s <= '1';
      wait for 10 ms;

      done_s(1) <= '1';

      wait;
    end process;

  end block;

  master: block is
  begin
    memap_mux: nsl_bnoc.framed.framed_arbitrer
      generic map(
        source_count => 2
        )
      port map(
        p_resetn => ate_reset_n_s,
        p_clk => ate_clock_s,

        p_cmd_val(0) => memap_rtt_s.cmd.req,
        p_cmd_val(1) => memap_ate_s.cmd.req,
        p_cmd_ack(0) => memap_rtt_s.cmd.ack,
        p_cmd_ack(1) => memap_ate_s.cmd.ack,
        p_rsp_val(0) => memap_rtt_s.rsp.req,
        p_rsp_val(1) => memap_ate_s.rsp.req,
        p_rsp_ack(0) => memap_rtt_s.rsp.ack,
        p_rsp_ack(1) => memap_ate_s.rsp.ack,
        
        p_target_cmd_val => memap_s.cmd.req,
        p_target_cmd_ack => memap_s.cmd.ack,
        p_target_rsp_val => memap_s.rsp.req,
        p_target_rsp_ack => memap_s.rsp.ack
        );

--    snooper_cmd: process is
--    begin
--      nsl_bnoc.testing.framed_snooper("dp cmd", dp_s.cmd, ate_clock_s, 65536, ate_clock_period_c);
--    end process;
--
--    snooper_rsp: process is
--    begin
--      nsl_bnoc.testing.framed_snooper("dp rsp", dp_s.rsp, ate_clock_s, 65536, ate_clock_period_c);
--    end process;

    memap: nsl_coresight.memap_mapper.framed_memap_transactor
      port map(
        clock_i  => ate_clock_s,
        reset_n_i => ate_reset_n_s,
        
        cmd_i => memap_s.cmd.req,
        cmd_o => memap_s.cmd.ack,
        rsp_o => memap_s.rsp.req,
        rsp_i => memap_s.rsp.ack,
        
        dp_cmd_o => dp_s.cmd.req,
        dp_cmd_i => dp_s.cmd.ack,
        dp_rsp_i => dp_s.rsp.req,
        dp_rsp_o => dp_s.rsp.ack
        );
    
    dp: nsl_coresight.transactor.dp_framed_transactor
      port map(
        clock_i  => ate_clock_s,
        reset_n_i => ate_reset_n_s,
        
        cmd_i => dp_s.cmd.req,
        cmd_o => dp_s.cmd.ack,
        rsp_o => dp_s.rsp.req,
        rsp_i => dp_s.rsp.ack,

        swd_o => master_swd_s.o,
        swd_i => master_swd_s.i
        );
  end block;
  
  dut: block is
    signal dapbus_gen, dapbus_memap : nsl_coresight.dapbus.dapbus_bus;
    signal mem_s : nsl_axi.axi4_mm.bus_t;
    constant config_c : nsl_axi.axi4_mm.config_t := nsl_axi.axi4_mm.config(address_width => 32, data_bus_width => 32);
    signal ctrl, ctrl_w, stat :std_ulogic_vector(31 downto 0);
    signal slave_swd_s : nsl_coresight.swd.swd_slave_bus;
  begin
    slave_swd_s.i <= to_slave(master_swd_s.o);
    master_swd_s.i <= to_master(slave_swd_s.o);

    dp: nsl_coresight.dp.swdp_sync
      generic map(
        idr => dp_idr_c
        )
      port map(
        ref_clock_i => dut_clock_s,
        ref_reset_n_i => dut_reset_n_s,

        swd_i => slave_swd_s.i,
        swd_o => slave_swd_s.o,

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

    snooper: nsl_axi.axi4_mm.axi4_mm_dumper
      generic map(
        config_c => config_c,
        prefix_c => "mem")
      port map(
        clock_i => dut_clock_s,
        reset_n_i => dut_reset_n_s,
        master_i => mem_s.m,
        slave_i => mem_s.s);
    
    mem_ap: nsl_coresight.ap.ap_axi4_lite
      generic map(
        rom_base => x"dead0001",
        config_c => config_c,
        idr => x"01234e11"
        )
      port map(
        clk_i => dut_clock_s,
        reset_n_i => dut_reset_n_s,

        dbgen_i => ctrl(28),
        spiden_i => '1',

        dap_i => dapbus_memap.ms,
        dap_o => dapbus_memap.sm,

        axi_o => mem_s.m,
        axi_i => mem_s.s
        );

    mem: nsl_axi.axi4_mm.axi4_mm_lite_ram
      generic map(
        byte_size_l2_c => 12,
        config_c => config_c
        )
      port map (
        clock_i => dut_clock_s,
        reset_n_i => dut_reset_n_s,

        axi_i => mem_s.m,
        axi_o => mem_s.s
        );
  end block;

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 2,
      reset_count => 2,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => ate_clock_period_c,
      clock_period(1) => dut_clock_period_c,
      reset_duration(0) => 42 ns,
      reset_duration(1) => 42 ns,
      reset_n_o(0) => ate_reset_n_s,
      reset_n_o(1) => dut_reset_n_s,
      clock_o(0) => ate_clock_s,
      clock_o(1) => dut_clock_s,
      done_i => done_s
      );

end;
