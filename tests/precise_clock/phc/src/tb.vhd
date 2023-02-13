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

  signal sub_nanosecond_inc_s : ufixed(7 downto -15);
  signal nanosecond_adj_s : timestamp_nanosecond_offset_t;
  signal timestamp_s, rtc_s : timestamp_t;
  signal nanosecond_adj_set_s, timestamp_set_s : std_ulogic;

begin

  st: process
  begin
    done_s <= "0";
    sub_nanosecond_inc_s <= to_ufixed(0.0, sub_nanosecond_inc_s'left, sub_nanosecond_inc_s'right);
    timestamp_s.second <= (others => '-');
    timestamp_s.nanosecond <= (others => '-');
    nanosecond_adj_set_s <= '0';
    nanosecond_adj_s <= (others => '-');
    timestamp_set_s <= '0';
    
    wait for clock_period_c * 10;
    wait until rising_edge(clock_s);

    sub_nanosecond_inc_s <= to_ufixed(clock_period_ns_c, sub_nanosecond_inc_s'left, sub_nanosecond_inc_s'right);
    wait for clock_period_c * 10;

    wait until falling_edge(clock_s);
    nanosecond_adj_s <= to_signed(integer(1.0e9 - clock_period_ns_c * 20.0), nanosecond_adj_s'length);
    nanosecond_adj_set_s <= '1';
    wait until rising_edge(clock_s);
    wait until falling_edge(clock_s);
    nanosecond_adj_s <= (others => '-');
    nanosecond_adj_set_s <= '0';
    wait for clock_period_c * 30;

    wait until falling_edge(clock_s);
    nanosecond_adj_s <= to_signed(integer(-0.5e9), nanosecond_adj_s'length);
    nanosecond_adj_set_s <= '1';
    wait until rising_edge(clock_s);
    wait until falling_edge(clock_s);
    nanosecond_adj_set_s <= '0';
    nanosecond_adj_s <= (others => '-');
    wait for clock_period_c * 10;

    wait until falling_edge(clock_s);
    nanosecond_adj_s <= to_signed(integer(0.25e9), nanosecond_adj_s'length);
    nanosecond_adj_set_s <= '1';
    wait until rising_edge(clock_s);
    wait until falling_edge(clock_s);
    nanosecond_adj_set_s <= '0';
    nanosecond_adj_s <= (others => '-');
    wait for clock_period_c * 10;

    wait until falling_edge(clock_s);
    nanosecond_adj_s <= to_signed(integer(0.25e9), nanosecond_adj_s'length);
    nanosecond_adj_set_s <= '1';
    wait until rising_edge(clock_s);
    wait until falling_edge(clock_s);
    nanosecond_adj_set_s <= '0';
    nanosecond_adj_s <= (others => '-');
    wait for clock_period_c * 10;

    wait until falling_edge(clock_s);
    timestamp_s.second <= to_unsigned(0, timestamp_s.second'length);
    timestamp_s.nanosecond <= to_unsigned(0, timestamp_s.nanosecond'length);
    timestamp_set_s <= '1';
    wait until rising_edge(clock_s);
    wait until falling_edge(clock_s);
    timestamp_s.second <= (others => '-');
    timestamp_s.nanosecond <= (others => '-');
    timestamp_set_s <= '0';
    wait for clock_period_c * 10;

    wait until falling_edge(clock_s);
    timestamp_s.second <= to_unsigned(42, timestamp_s.second'length);
    timestamp_s.nanosecond <= to_unsigned(999999900, timestamp_s.nanosecond'length);
    timestamp_set_s <= '1';
    wait until rising_edge(clock_s);
    wait until falling_edge(clock_s);
    timestamp_s.second <= (others => '-');
    timestamp_s.nanosecond <= (others => '-');
    timestamp_set_s <= '0';
    wait for clock_period_c * 10;

    wait until falling_edge(clock_s);
    timestamp_s.second <= to_unsigned(100, timestamp_s.second'length);
    timestamp_s.nanosecond <= to_unsigned(0, timestamp_s.nanosecond'length);
    timestamp_set_s <= '1';
    wait until rising_edge(clock_s);
    wait until falling_edge(clock_s);
    timestamp_s.second <= (others => '-');
    timestamp_s.nanosecond <= (others => '-');
    timestamp_set_s <= '0';
    wait for clock_period_c * 10;

    wait until falling_edge(clock_s);
    nanosecond_adj_s <= to_signed(-200, nanosecond_adj_s'length);
    nanosecond_adj_set_s <= '1';
    wait until rising_edge(clock_s);
    wait until falling_edge(clock_s);
    nanosecond_adj_set_s <= '0';
    nanosecond_adj_s <= (others => '-');
    wait for clock_period_c * 3;

    wait until falling_edge(clock_s);
    nanosecond_adj_s <= to_signed(-25, nanosecond_adj_s'length);
    nanosecond_adj_set_s <= '1';
    wait until rising_edge(clock_s);
    wait until falling_edge(clock_s);
    nanosecond_adj_set_s <= '0';
    nanosecond_adj_s <= (others => '-');
    wait for clock_period_c * 3;

    wait until falling_edge(clock_s);
    nanosecond_adj_s <= to_signed(-51, nanosecond_adj_s'length);
    nanosecond_adj_set_s <= '1';
    wait until rising_edge(clock_s);
    wait until falling_edge(clock_s);
    nanosecond_adj_set_s <= '0';
    nanosecond_adj_s <= (others => '-');
    wait for clock_period_c * 3;

    wait for clock_period_c * 40;

    done_s <= "1";
    wait;
  end process;
  
  dut: nsl_time.phc.ptp_hardware_clock
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      sub_nanosecond_inc_i => sub_nanosecond_inc_s,

      nanosecond_adj_i => nanosecond_adj_s,
      nanosecond_adj_set_i => nanosecond_adj_set_s,

      timestamp_i => timestamp_s,
      timestamp_set_i => timestamp_set_s,

      timestamp_o => rtc_s
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
