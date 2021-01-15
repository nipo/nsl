library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library design;

entity testbench is
end testbench;

library nsl_clocking, nsl_bnoc, nsl_coresight, nsl_simulation;

architecture arch of testbench is

  signal s_clk : std_ulogic := '0';
  signal s_resetn_clk : std_ulogic;
  signal s_resetn_async : std_ulogic;

  signal swdio : std_logic;
  signal s_swd_master_o : nsl_coresight.swd.swd_master_o;
  signal s_swd_master_i : nsl_coresight.swd.swd_master_i;
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

  signal s_cmd_fifo, s_rsp_fifo : nsl_bnoc.framed.framed_bus;
  signal s_swd_cmd, s_swd_rsp : nsl_bnoc.framed.framed_bus;

begin

  reset_sync_clk: nsl_clocking.async.async_edge
    port map(
      data_i => s_resetn_async,
      data_o => s_resetn_clk,
      clock_i => s_clk
      );

  target: design.fpga_io.swd_main
    port map(
      led => open,
      swclk => s_swd_master_o.clk,
      swdio => swdio
      );

  swdio <= s_swd_master_o.dio.v when s_swd_master_o.dio.output = '1' else 'H';
  s_swd_master_i.dio <= to_x01(swdio);

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

      swd_o => s_swd_master_o,
      swd_i => s_swd_master_i
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
      reset_duration(0) => 35 ns,
      reset_n_o(0) => s_resetn_async,
      clock_o(0) => s_clk,
      done_i => s_done
      );

end;
