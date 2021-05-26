library ieee;
use ieee.std_logic_1164.all;

entity tb is
end tb;

library nsl_signal_generator, nsl_math, nsl_simulation;
use nsl_math.fixed.all;

architecture arch of tb is

  constant internal_clock_freq : integer := 240000000;

  signal s_clock : std_ulogic;
  signal s_reset_n : std_ulogic;
  signal s_value : sfixed(0 downto -10);
  signal s_value_r : real;
  signal s_freq_r : real;
  signal s_angle_increment : ufixed(-1 downto -20);
  signal s_done : std_ulogic_vector(0 to 0);

begin

  nco: nsl_signal_generator.nco.nco_sinus
    generic map(
      trim_bits_c => 10,
      implementation_c => "table"
      )
    port map(
      clock_i => s_clock,
      reset_n_i => s_reset_n,
      angle_increment_i => s_angle_increment,
      value_o => s_value
      );

  s_value_r <= to_real(s_value);
  s_angle_increment <= to_ufixed(2.0 / real(internal_clock_freq) * s_freq_r,
                                 s_angle_increment'left,
                                 s_angle_increment'right);

  st: process
  begin
    s_done <= "0";

    s_freq_r <= 1.0e6;
    wait for 8 us;
    
    s_freq_r <= 2.0e6;
    wait for 8 us;
    
    s_freq_r <= 100.0e6;
    wait for 8 us;
    
    s_freq_r <= 1.0e3;
    wait for 3 ms;
    
    s_done <= "1";
    wait;
  end process;

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
