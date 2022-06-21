library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb is
end tb;

library nsl_clocking, nsl_bnoc, nsl_coresight, nsl_simulation;

architecture arch of tb is

  signal s_clk : std_ulogic := '0';
  signal s_resetn_clk : std_ulogic;
  signal s_resetn_async : std_ulogic;

  signal s_probe_master_o : nsl_coresight.swd.swd_master_o;
  signal s_probe_master_i : nsl_coresight.swd.swd_master_i;
  signal s_probe_slave_o : nsl_coresight.swd.swd_slave_o;
  signal s_probe_slave_i : nsl_coresight.swd.swd_slave_i;

  signal s_target_master_o : nsl_coresight.swd.swd_master_o;
  signal s_target_master_i : nsl_coresight.swd.swd_master_i;
  signal s_target_slave_o : nsl_coresight.swd.swd_slave_o;
  signal s_target_slave_i : nsl_coresight.swd.swd_slave_i;

  signal s_srst : std_logic;

  signal s_ap_resetn : std_ulogic;
  signal s_ap_sel : unsigned(7 downto 0);
  signal s_ap_a : unsigned(5 downto 0);
  signal s_ap_rdata : unsigned(31 downto 0);
  signal s_ap_ready : std_ulogic;
  signal s_ap_rok : std_ulogic;
  signal s_ap_ren : std_ulogic;
  signal s_ap_wdata : unsigned(31 downto 0);
  signal s_ap_wen : std_ulogic;

  signal s_done : std_ulogic_vector(0 to 1);

  type framed_io is
  record
    req: nsl_bnoc.framed.framed_req;
    ack: nsl_bnoc.framed.framed_ack;
  end record;

  signal s_swd_cmd, s_swd_rsp, s_cmd_fifo, s_rsp_fifo : framed_io;

  procedure swd_resolve(signal master_o: out nsl_coresight.swd.swd_master_i;
                        signal slave_o: out nsl_coresight.swd.swd_slave_i;
                        signal master_i: in nsl_coresight.swd.swd_master_o;
                        signal slave_i: in nsl_coresight.swd.swd_slave_o) is
    variable dio : std_logic;
  begin
    if master_i.dio.output = '1' and slave_i.dio.output = '1' then
      assert false
        report "Write conflict on SWDIO line"
        severity warning;
      dio := 'X';
    elsif master_i.dio.output = '1' and slave_i.dio.output = '0' then
      dio := master_i.dio.v;
    elsif slave_i.dio.output = '1' and master_i.dio.output = '0' then
      dio := slave_i.dio.v;
    else
      dio := 'H';
    end if;

    slave_o.clk <= master_i.clk;
    slave_o.dio <= dio;
    master_o.dio <= dio;
  end procedure;
  
begin

  reset_sync_clk: nsl_clocking.async.async_edge
    port map(
      data_i => s_resetn_async,
      data_o => s_resetn_clk,
      clock_i => s_clk
      );

  probe_swdio: process (s_probe_master_o, s_probe_slave_o)
  begin
    swd_resolve(s_probe_master_i, s_probe_slave_i, s_probe_master_o, s_probe_slave_o);
  end process;

  target_swd: process (s_target_master_o, s_target_slave_o)
  begin
    swd_resolve(s_target_master_i, s_target_slave_i, s_target_master_o, s_target_slave_o);
  end process;

  router: nsl_coresight.swd_multidrop.swd_multidrop_router
    generic map(
      targetsel_base_c => x"dead123",
      target_count_c => 1
      )
    port map(
      reset_n_i => s_resetn_async,

      muxed_i => s_probe_slave_i,
      muxed_o => s_probe_slave_o,

      target_o(0) => s_target_master_o,
      target_i(0) => s_target_master_i
      );
  
  swdap: nsl_coresight.testing.swdap
    port map(
      p_swd_c => s_target_slave_o,
      p_swd_s => s_target_slave_i,

      p_swd_resetn => s_ap_resetn,
      p_ap_sel => s_ap_sel,
      p_ap_a => s_ap_a,
      p_ap_rdata => s_ap_rdata,
      p_ap_ready => s_ap_ready,
      p_ap_ren => s_ap_ren,
      p_ap_rok => s_ap_rok,
      p_ap_wdata => s_ap_wdata,
      p_ap_wen => s_ap_wen
      );

  ap: nsl_coresight.testing.ap_sim
    port map(
      p_clk => s_target_slave_i.clk,
      p_resetn => s_ap_resetn,
      p_ap => s_ap_sel,
      p_a => s_ap_a,
      p_rdata => s_ap_rdata,
      p_ready => s_ap_ready,
      p_ren => s_ap_ren,
      p_rok => s_ap_rok,
      p_wdata => s_ap_wdata,
      p_wen => s_ap_wen
      );

  swd_endpoint: nsl_bnoc.routed.routed_endpoint
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,

      p_cmd_in_val => s_cmd_fifo.req,
      p_cmd_in_ack => s_cmd_fifo.ack,
      p_rsp_out_val => s_rsp_fifo.req,
      p_rsp_out_ack => s_rsp_fifo.ack,
      
      p_cmd_out_val => s_swd_cmd.req,
      p_cmd_out_ack => s_swd_cmd.ack,
      p_rsp_in_val => s_swd_rsp.req,
      p_rsp_in_ack => s_swd_rsp.ack
      );

  dp: nsl_coresight.transactor.dp_framed_transactor
    port map(
      clock_i  => s_clk,
      reset_n_i => s_resetn_clk,
      
      cmd_i => s_swd_cmd.req,
      cmd_o => s_swd_cmd.ack,

      rsp_o => s_swd_rsp.req,
      rsp_i => s_swd_rsp.ack,

      swd_o => s_probe_master_o,
      swd_i => s_probe_master_i
      );

  gen: nsl_bnoc.testing.framed_file_reader
    generic map(
      filename => "swd_commands.txt"
      )
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,
      p_out_val => s_cmd_fifo.req,
      p_out_ack => s_cmd_fifo.ack,
      p_done => s_done(0)
      );

  check0: nsl_bnoc.testing.framed_file_checker
    generic map(
      filename => "swd_responses.txt"
      )
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,
      p_in_val => s_rsp_fifo.req,
      p_in_ack => s_rsp_fifo.ack,
      p_done => s_done(1)
      );

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => s_done'length
      )
    port map(
      clock_period(0) => 10 ns,
      reset_duration(0) => 100 ns,
      reset_n_o(0) => s_resetn_async,
      clock_o(0) => s_clk,
      done_i => s_done
      );

end;
