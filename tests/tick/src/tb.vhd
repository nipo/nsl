library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb is
end tb;

library nsl_clocking, nsl_simulation, nsl_math, nsl_event;
use nsl_math.fixed.all;

architecture arch of tb is

  signal s_clk : std_ulogic_vector(0 to 1);
  signal s_resetn_clk : std_ulogic_vector(0 to 1);
  signal s_resetn_async : std_ulogic;

  signal s_gen_tick, s_rcv_tick : std_ulogic;
  constant c_period: ufixed(4 downto -5) := to_ufixed(10.0, 4, -5);
  constant c_unit: ufixed(c_period'range) := to_ufixed(1.0, c_period'left, c_period'right);
  signal s_period: nsl_math.fixed.ufixed(6 downto -8);

  signal s_done : std_ulogic_vector(0 to 0);

begin

  reset_sync0: nsl_clocking.async.async_edge
    port map(
      data_i => s_resetn_async,
      data_o => s_resetn_clk(0),
      clock_i => s_clk(0)
      );

  reset_sync1: nsl_clocking.async.async_edge
    port map(
      data_i => s_resetn_async,
      data_o => s_resetn_clk(1),
      clock_i => s_clk(1)
      );

  freq_gen: nsl_event.tick.tick_generator_frac
    port map(
      reset_n_i => s_resetn_clk(0),
      clock_i => s_clk(0),
      freq_denom_i => c_period,
      freq_num_i => c_unit,
      tick_o => s_gen_tick
      );

  tick_txn: nsl_clocking.interdomain.interdomain_tick
    port map(
      input_clock_i => s_clk(0),
      output_clock_i => s_clk(1),
      input_reset_n_i => s_resetn_clk(0),
      tick_i => s_gen_tick,
      tick_o => s_rcv_tick
      );

  measurer : nsl_event.tick.tick_measurer
    generic map(
      tau_c => 2**(s_period'length)-1
      )
    port map(
      clock_i => s_clk(1),
      reset_n_i => s_resetn_clk(1),
      tick_i => s_rcv_tick,
      period_o => s_period
      );
  
  stim: process
  begin
    s_done <= "0";
    wait for 2 ms;
    s_done <= "1";
    wait;
  end process;
  
  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 2,
      reset_count => 1,
      done_count => s_done'length
      )
    port map(
      clock_period(0) => 16276 ps, -- 61.44 MHz
      clock_period(1) => 6666 ps, -- 150 MHz
      reset_duration(0) => 100 ns,
      reset_n_o(0) => s_resetn_async,
      clock_o => s_clk,
      done_i => s_done
      );

end;
