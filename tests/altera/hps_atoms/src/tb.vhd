library ieee;
use ieee.std_logic_1164.all;

library nsl_altera, nsl_simulation;
use nsl_altera.hps.all;

-- Elaborates the atom layer generated from hps.yaml, with the atoms
-- left unbound: checks the generated VHDL and its agreement with the
-- bridge generics.
entity tb is
end tb;

architecture arch of tb is

  signal done_s : std_ulogic_vector(0 to 0);
  signal io_i_s, io_o_s : std_ulogic_vector(0 to 47);
  signal io_io_s : std_logic_vector(0 to 47);
  signal h2f_o_s, lwh2f_o_s : hps_master_fwd_t;
  signal h2f_i_s, lwh2f_i_s : hps_master_bwd_t;
  signal f2h_i_s, f2sdram_i_s : hps_slave_fwd_t;
  signal f2h_o_s, f2sdram_o_s : hps_slave_bwd_t;
  signal emif_o_s : hps_emif_o_t;
  signal clock_s : std_ulogic;

begin

  atoms: nsl_altera.hps.hps_atoms
    generic map(
      h2f_used_c => true,
      h2f_data_width_c => 128,
      lwh2f_used_c => true,
      lwh2f_data_width_c => 32,
      f2h_used_c => true,
      f2h_data_width_c => 256,
      f2h_ace_c => hps_f2h_non_coherent_c,
      f2sdram_used_c => true,
      f2sdram_data_width_c => 256,
      emif_used_c => true
      )
    port map(
      hps_io_i => io_i_s,
      hps_io_o => io_o_s,
      hps_io_io => io_io_s,
      h2f_reset_o => open,
      user_clock_o => open,
      warm_reset_request_n_o => open,
      warm_reset_ack_n_i => '1',
      irq_i => (others => '0'),
      gp_i => (others => '0'),
      gp_o => open,
      h2f_clock_i => clock_s,
      h2f_o => h2f_o_s,
      h2f_i => h2f_i_s,
      lwh2f_clock_i => clock_s,
      lwh2f_o => lwh2f_o_s,
      lwh2f_i => lwh2f_i_s,
      f2h_clock_i => clock_s,
      f2h_i => f2h_i_s,
      f2h_o => f2h_o_s,
      f2sdram_clock_i => clock_s,
      f2sdram_i => f2sdram_i_s,
      f2sdram_o => f2sdram_o_s,
      emif_o => emif_o_s,
      emif_i => hps_emif_i_idle_c
      );

  io_i_s <= (others => '0');
  done_s <= "1";

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 10 ns,
      reset_duration(0) => 10 ns,
      clock_o(0) => clock_s,
      done_i => done_s
      );

end;
