library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity tb is
end tb;

library nsl_dsp, nsl_math, nsl_simulation;
use nsl_simulation.logging.all;
use nsl_math.fixed.all;

architecture arch of tb is
  
  constant internal_clock_freq : integer := 100e6;

  signal s_clock : std_ulogic;
  signal s_reset_n : std_ulogic;

  signal update_s : std_ulogic;

  constant f_l2_c : integer := 7;
  
  signal s_value, s_rc, s_box : ufixed(1 downto -16);
  signal s_value_r, s_rc_r, s_box_r : real;
  signal s_done : std_ulogic_vector(0 to 0);

begin

  s_box_r <= to_real(s_box);
  s_rc_r <= to_real(s_rc);
  s_value <= to_ufixed(s_value_r, s_value'left, s_value'right);
  
  st: process
  begin
    s_done <= "0";
    s_value_r <= 0.0;
    wait for 1 ns;

    wait until s_reset_n = '1';
    wait for 80 us;

    s_value_r <= 1.0;
    wait for 80 us;

    s_value_r <= 0.0;
    wait for 80 us;

    s_value_r <= 0.5;
    wait for 80 us;

    s_value_r <= 1.0;
    wait for 80 us;
    
    s_done <= "1";
    wait;
  end process;
  
  up: process
  begin
    update_s <= '0';
    while true
    loop
      wait until falling_edge(s_clock);
      update_s <= '1';
      wait until falling_edge(s_clock);
      update_s <= '0';
      wait for 40 ns;
    end loop;
    

    wait;
  end process;

  box: nsl_dsp.box.box_ufixed
    generic map(
      count_l2_c => f_l2_c
      )
    port map(
      clock_i => s_clock,
      reset_n_i => s_reset_n,

      valid_i => update_s,
      in_i => s_value,
      out_o => s_box
      );

  rc: nsl_dsp.rc.rc_ufixed
    generic map(
      tau_c => (2 ** f_l2_c) - 1
      )
    port map(
      clock_i => s_clock,
      reset_n_i => s_reset_n,

      valid_i => update_s,
      in_i => s_value,
      out_o => s_rc
      );

  
  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => s_done'length
      )
    port map(
      clock_period(0) => 1000000 ps / (internal_clock_freq / 1000000),
      reset_duration(0) => 1 us,
      reset_n_o(0) => s_reset_n,
      clock_o(0) => s_clock,
      done_i => s_done
      );
  
end;
