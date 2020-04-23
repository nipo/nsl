library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb is
end tb;

library nsl_simulation, nsl_bnoc, nsl_mii, nsl_clocking;

architecture arch of tb is

  signal s_clk : std_ulogic := '0';
  signal s_resetn_clk : std_ulogic;
  signal s_resetn_async : std_ulogic;

  signal s_framed : nsl_bnoc.framed.framed_bus_array(0 to 1);
  signal s_mii_data   : nsl_mii.mii.mii_datapath;

  signal s_done : std_ulogic_vector(0 to 1);

begin

  reset_sync_clk: nsl_clocking.async.async_edge
    port map(
      data_i => s_resetn_async,
      data_o => s_resetn_clk,
      clock_i => s_clk
      );

  gen: nsl_bnoc.testing.framed_file_reader
    generic map(
      filename => "dataset.txt"
      )
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,
      p_out_val => s_framed(0).req,
      p_out_ack => s_framed(0).ack,
      p_done => s_done(0)
      );

  check0: nsl_bnoc.testing.framed_file_checker
    generic map(
      filename => "dataset.txt"
      )
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,
      p_in_val => s_framed(1).req,
      p_in_ack => s_framed(1).ack,
      p_done => s_done(1)
      );

  to_mii: nsl_mii.framed.mii_from_framed
    port map(
      reset_n_i => s_resetn_clk,
      clock_i => s_clk,
      mii_o => s_mii_data,
      framed_i => s_framed(0).req,
      framed_o => s_framed(0).ack
      );

  from_mii: nsl_mii.framed.mii_to_framed
    port map(
      reset_n_i => s_resetn_clk,
      clock_i => s_clk,
      mii_i => s_mii_data,
      framed_o => s_framed(1).req
      );

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => 2
      )
    port map(
      clock_period(0) => 5 ns,
      reset_duration(0) => 100 ns,
      reset_n_o(0) => s_resetn_async,
      clock_o(0) => s_clk,
      done_i => s_done
      );

end;
