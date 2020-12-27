library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb is
end tb;

library nsl_clocking, nsl_bnoc, nsl_smi, nsl_simulation;

architecture arch of tb is

  signal s_clk : std_ulogic := '0';
  signal s_resetn_clk : std_ulogic;
  signal s_resetn_async : std_ulogic;

  signal s_done : std_ulogic_vector(0 to 1);
  signal s_cmd, s_rsp : nsl_bnoc.framed.framed_bus;
  signal smi_i : nsl_smi.smi.smi_master_i;
  signal smi_o : nsl_smi.smi.smi_master_o;

begin

  smi_i.mdio <= smi_o.mdio.v when smi_o.mdio.output = '1' else 'H';

  reset_sync_clk: nsl_clocking.async.async_edge
    port map(
      data_i => s_resetn_async,
      data_o => s_resetn_clk,
      clock_i => s_clk
      );

  smi_master: nsl_smi.transactor.smi_framed_transactor
    port map(
      clock_i => s_clk,
      reset_n_i => s_resetn_clk,
      
      smi_o => smi_o,
      smi_i => smi_i,

      cmd_i => s_cmd.req,
      cmd_o => s_cmd.ack,
      rsp_i => s_rsp.ack,
      rsp_o => s_rsp.req
      );

  gen: nsl_bnoc.testing.framed_file_reader
    generic map(
      filename => "smi_commands.txt"
      )
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,
      p_out_val => s_cmd.req,
      p_out_ack => s_cmd.ack,
      p_done => s_done(0)
      );

  check0: nsl_bnoc.testing.framed_file_checker
    generic map(
      filename => "smi_responses.txt"
      )
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,
      p_in_val => s_rsp.req,
      p_in_ack => s_rsp.ack,
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
