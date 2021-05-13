library ieee;
use ieee.std_logic_1164.all;

entity tb is
end tb;

library nsl_dsp, nsl_math, nsl_simulation;
use nsl_math.fixed.all;

architecture arch of tb is

  constant internal_clock_freq : integer := 240000000;
  constant symbol_per_s : integer := 1000000;

  signal s_clock : std_ulogic;
  signal s_reset_n : std_ulogic;

  signal s_mi_i_f, s_mi_o_f : ufixed(-1 downto -10);
  signal s_mi_i_r, s_mi_o_r : real;
  signal s_done : std_ulogic_vector(0 to 0);

begin

  s_mi_i_r <= to_real(s_mi_i_f);
  s_mi_o_r <= to_real(s_mi_o_f);

  st: process
  begin
    s_done <= "0";

    s_mi_i_f <= (others => '0');
    wait for 1 us;
    s_mi_i_f <= (others => '1');
    wait for 1 us;
    s_mi_i_f <= (others => '0');
    wait for 1 us;
    s_mi_i_f <= (others => '1');
    wait for 1 us;
    s_mi_i_f <= (others => '0');
    wait for 1 us;
    s_mi_i_f <= (others => '1');
    wait for 2 us;
    s_mi_i_f <= (others => '0');
    wait for 2 us;
    s_mi_i_f <= (others => '1');
    wait for 2 us;
    s_mi_i_f <= (others => '0');
    wait for 2 us;
    s_mi_i_f <= (others => '1');
    wait for 2 us;
    
    s_done <= "1";
    wait;
  end process;

  filter: nsl_dsp.gaussian.gaussian_approx_ufixed
    generic map(
      symbol_sample_count_c => internal_clock_freq / symbol_per_s,
      bt_c => 0.5
      )
    port map(
      clock_i => s_clock,
      reset_n_i => s_reset_n,

      in_i => s_mi_i_f,
      out_o => s_mi_o_f
      );
  
  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => s_done'length
      )
    port map(
      clock_period(0) => 1000000 ps / (internal_clock_freq / 1000000),
      reset_duration(0) => 10 ns,
      reset_n_o(0) => s_reset_n,
      clock_o(0) => s_clock,
      done_i => s_done
      );
    
end;
