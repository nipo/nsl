library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library nsl_time, nsl_simulation, nsl_math, work;
use nsl_math.timing.all;
use nsl_math.fixed.all;
use nsl_time.timestamp.all;

entity tb is
end tb;

architecture arch of tb is

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 0);

  constant clock_freq_c : real := 80.0e6;
  constant clock_period_c : time := seconds_to_time(1.0 / clock_freq_c);
  constant clock_period_ns_c : real := 1.0e9 / clock_freq_c;

  signal a_inc_s : ufixed(7 downto -15);
  signal a_adj_s : timestamp_nanosecond_offset_t;
  signal a_force_s, a_time_s : timestamp_t;
  signal a_adj_set_s, a_force_set_s : std_ulogic;

  signal b_inc_s : ufixed(7 downto -15);
  signal b_adj_s : timestamp_nanosecond_offset_t;
  signal b_force_s, b_time_s : timestamp_t;
  signal b_adj_set_s, b_force_set_s : std_ulogic;

  signal c_time_s : timestamp_t;

  signal measured_offset_s : timestamp_nanosecond_offset_t;
  
begin

  st: process
  begin
    done_s <= "0";
    a_inc_s <= to_ufixed(0.0, a_inc_s'left, a_inc_s'right);
    a_force_s.second <= (others => '-');
    a_force_s.nanosecond <= (others => '-');
    a_adj_set_s <= '0';
    a_adj_s <= (others => '-');
    a_force_set_s <= '0';

    b_inc_s <= to_ufixed(0.0, b_inc_s'left, b_inc_s'right);
    b_force_s.second <= (others => '-');
    b_force_s.nanosecond <= (others => '-');
    b_adj_set_s <= '0';
    b_adj_s <= (others => '-');
    b_force_set_s <= '0';
    
    wait for clock_period_c * 10;
    wait until rising_edge(clock_s);

    wait until falling_edge(clock_s);
    a_force_s.second <= to_unsigned(1, a_force_s.second'length);
    a_force_s.nanosecond <= to_unsigned(0, a_force_s.nanosecond'length);
    a_force_set_s <= '1';
    b_force_s.second <= to_unsigned(1, b_force_s.second'length);
    b_force_s.nanosecond <= to_unsigned(0, b_force_s.nanosecond'length);
    b_force_set_s <= '1';
    wait until rising_edge(clock_s);
    wait until falling_edge(clock_s);
    a_force_s.second <= (others => '-');
    a_force_s.nanosecond <= (others => '-');
    a_force_set_s <= '0';
    b_force_s.second <= (others => '-');
    b_force_s.nanosecond <= (others => '-');
    b_force_set_s <= '0';
    wait for clock_period_c * 10;

    wait until falling_edge(clock_s);
    a_inc_s <= to_ufixed(12.475, a_inc_s'left, a_inc_s'right);
    b_inc_s <= to_ufixed(12.505, b_inc_s'left, b_inc_s'right);

    wait for clock_period_c * 100;

    wait until falling_edge(clock_s);
    a_adj_s <= to_signed(-2000, a_adj_s'length);
    a_adj_set_s <= '1';
    b_adj_s <= to_signed(-2000, b_adj_s'length);
    b_adj_set_s <= '1';
    wait until rising_edge(clock_s);
    wait until falling_edge(clock_s);
    a_adj_set_s <= '0';
    a_adj_s <= (others => '-');
    b_adj_set_s <= '0';
    b_adj_s <= (others => '-');

    wait for clock_period_c * 100;

    wait until falling_edge(clock_s);
    b_adj_s <= to_signed(-7, b_adj_s'length);
    b_adj_set_s <= '1';
    wait until rising_edge(clock_s);
    wait until falling_edge(clock_s);
    b_adj_set_s <= '0';
    b_adj_s <= (others => '-');

    wait for clock_period_c * 100;

    wait until falling_edge(clock_s);
    a_adj_s <= to_signed(-4000, a_adj_s'length);
    a_adj_set_s <= '1';
    b_adj_s <= to_signed(-4000, b_adj_s'length);
    b_adj_set_s <= '1';
    wait until rising_edge(clock_s);
    wait until falling_edge(clock_s);
    a_adj_set_s <= '0';
    a_adj_s <= (others => '-');
    b_adj_set_s <= '0';
    b_adj_s <= (others => '-');

    wait for clock_period_c * 10;

    wait until falling_edge(clock_s);
    a_inc_s <= to_ufixed(12.505, a_inc_s'left, a_inc_s'right);
    b_inc_s <= to_ufixed(12.473, b_inc_s'left, b_inc_s'right);

    wait for clock_period_c * 100;

    wait until falling_edge(clock_s);
    a_adj_s <= to_signed(-7, a_adj_s'length);
    a_adj_set_s <= '1';
    wait until rising_edge(clock_s);
    wait until falling_edge(clock_s);
    a_adj_set_s <= '0';
    a_adj_s <= (others => '-');

    wait for clock_period_c * 100;

    
    done_s <= "1";
    wait;
  end process;
  
  a_inst: nsl_time.phc.ptp_hardware_clock
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      sub_nanosecond_inc_i => a_inc_s,

      nanosecond_adj_i => a_adj_s,
      nanosecond_adj_set_i => a_adj_set_s,

      timestamp_i => a_force_s,
      timestamp_set_i => a_force_set_s,

      timestamp_o => a_time_s
      );
  
  b_inst: nsl_time.phc.ptp_hardware_clock
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      sub_nanosecond_inc_i => b_inc_s,

      nanosecond_adj_i => b_adj_s,
      nanosecond_adj_set_i => b_adj_set_s,

      timestamp_i => b_force_s,
      timestamp_set_i => b_force_set_s,

      timestamp_o => b_time_s
      );

  compare: nsl_time.skew.skew_measurer
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      reference_i => a_time_s,
      skewed_i => b_time_s,

      offset_o => measured_offset_s
      );

  offset: nsl_time.skew.skew_offsetter
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      reference_i => a_time_s,
      offset_i => measured_offset_s,

      skewed_o => c_time_s
      );
  
  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => clock_period_c,
      reset_duration(0) => clock_period_c * 3,
      reset_n_o(0) => reset_n_s,
      clock_o(0) => clock_s,
      done_i => done_s
      );

end;
