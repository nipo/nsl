library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb is
end tb;

library nsl_clocking, nsl_bnoc, nsl_coresight, nsl_simulation, nsl_data, nsl_axi;
use nsl_coresight.testing.all;
use nsl_bnoc.testing.all;
use nsl_data.bytestream.all;
use nsl_data.text.all;
use nsl_simulation.logging.all;
use nsl_coresight.swd.all;

architecture arch of tb is

  constant dut_clock_period_c : time := 20 ns;
  constant ate_clock_period_c : time := 10 ns;

  signal ate_clock_s : std_ulogic;
  signal ate_reset_n_s : std_ulogic;
  signal dut_clock_s : std_ulogic;
  signal dut_reset_n_s : std_ulogic;

  signal done_s : std_ulogic_vector(0 to 0);

  type framed_io is
  record
    cmd, rsp: nsl_bnoc.framed.framed_bus_t;
  end record;

  signal dp_s, memap_s : framed_io;
  signal master_swd_s : nsl_coresight.swd.swd_master_bus;

  constant dp_idr_c : unsigned := x"04567e11";
  
begin

    snooper_cmd: process is
    begin
      nsl_bnoc.testing.framed_snooper("ate cmd", memap_s.cmd, ate_clock_s, 65536, ate_clock_period_c);
    end process;

    snooper_rsp: process is
    begin
      nsl_bnoc.testing.framed_snooper("ate rsp", memap_s.rsp, ate_clock_s, 65536, ate_clock_period_c);
    end process;

  ate: block is
    constant cpol_c: std_ulogic := '0';
    constant cpha_c: std_ulogic := '0';

    shared variable ate_rsp_v, ate_cmd_v: framed_queue_root;

  begin

    ate_stim: process is
      variable dropped: byte_stream;
    begin
      done_s(0) <= '0';

      wait for 100 ns;

      memap_dp_swd_init("Init", ate_cmd_v, ate_rsp_v, dp_idr_c);
      memap_param_set("Params", ate_cmd_v, ate_rsp_v, x"800000", 4);
      memap_write("Write", ate_cmd_v, ate_rsp_v, x"00000000", from_hex("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"));
      memap_read_check("Read", ate_cmd_v, ate_rsp_v, x"00000008", from_hex("08090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"));
      memap_read_check("Read", ate_cmd_v, ate_rsp_v, x"00000001", from_hex("0102030405060708090a"));
      memap_write("Write16", ate_cmd_v, ate_rsp_v, x"00000008", from_hex("998877"));
      memap_read_check("Read", ate_cmd_v, ate_rsp_v, x"00000008", from_hex("9988770b0c0d0e0f"));
      memap_read8_check("Read8/0", ate_cmd_v, ate_rsp_v, from_hex("10"), 0);
      memap_read8_check("Read8/1", ate_cmd_v, ate_rsp_v, from_hex("11"), 1);
      memap_read8_check("Read8/2", ate_cmd_v, ate_rsp_v, from_hex("12"), 2);
      memap_read8_check("Read8/3", ate_cmd_v, ate_rsp_v, from_hex("13"), 3);
      memap_read16_check("Read16", ate_cmd_v, ate_rsp_v, from_hex("1415"), 0);
      memap_read16_check("Read16", ate_cmd_v, ate_rsp_v, from_hex("1617"), 2);
      
      wait for 3000 ns;
      
      done_s(0) <= '1';
      wait;
    end process;

    memap_s_rsp_reader: process is
      variable data: byte_stream;
    begin
      framed_queue_init(ate_rsp_v);

      while true
      loop
        framed_get(memap_s.rsp.req, memap_s.rsp.ack, ate_clock_s, data);
        --log_info("ATE < " & to_string(data.all));
        framed_queue_put(ate_rsp_v, data.all);
        deallocate(data);
      end loop;
    end process;

    memap_s_cmd_writer: process is
      variable data: byte_stream;
    begin
      framed_queue_init(ate_cmd_v);

      while true
      loop
        framed_wait(memap_s.cmd.req, memap_s.cmd.ack, ate_clock_s, 1);
        framed_queue_get(ate_cmd_v, data);
        --log_info("ATE > " & to_string(data.all));
        framed_put(memap_s.cmd.req, memap_s.cmd.ack, ate_clock_s, data.all);
        deallocate(data);
      end loop;
    end process;
  end block;
  
  master: block is

  begin
    

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
    signal mem_s : nsl_axi.axi4_lite.a32_d32;
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

    mem_ap: nsl_coresight.ap.axi4_lite_a32_d32_ap
      generic map(
        rom_base => x"dead0001",
        idr => x"01234e11"
        )
      port map(
        clk_i => dut_clock_s,
        reset_n_i => dut_reset_n_s,

        dbgen_i => ctrl(28),
        spiden_i => '1',

        dap_i => dapbus_memap.ms,
        dap_o => dapbus_memap.sm,

        mem_o => mem_s.ms,
        mem_i => mem_s.sm
        );

    mem: nsl_axi.bram.axi4_lite_a32_d32_ram
      generic map (
        mem_size_log2_c => 12
        )
      port map (
        clock_i => dut_clock_s,
        reset_n_i => dut_reset_n_s,

        axi_i => mem_s.ms,
        axi_o => mem_s.sm
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
