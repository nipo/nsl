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

  constant clock_freq_c : real := 3.0e6;
  constant clock_period_c : time := seconds_to_time(1.0 / clock_freq_c);
  constant clock_period_ns_c : real := 1.0e9 / clock_freq_c;

  signal pps_tick_s: std_ulogic;
  signal rtc_slave_s: timestamp_t;

  procedure do_second(signal clock_i: in std_ulogic;
                      signal pps_o: out std_ulogic;
                      total_cycles: natural)
  is
  begin
    wait until falling_edge(clock_i);
    pps_o <= '1';
    wait until falling_edge(clock_i);
    pps_o <= '0';

    for i in 0 to total_cycles - 3
    loop
      wait until falling_edge(clock_i);
    end loop;
  end procedure;
  
begin

  st: process
  begin
    done_s <= "0";
    pps_tick_s <= '0';

    for i in 0 to 0
    loop
      do_second(clock_s, pps_tick_s, integer(clock_freq_c));
    end loop;

    for i in 0 to 1
    loop
      do_second(clock_s, pps_tick_s, integer(clock_freq_c) + 5);
    end loop;

    for i in 0 to 1
    loop
      do_second(clock_s, pps_tick_s, integer(clock_freq_c) - 5);
    end loop;
    

    
    done_s <= "1";
    wait;
  end process;

  clock_slave: nsl_time.clock.clock_from_pps
    generic map(
      clock_nominal_hz_c => integer(clock_freq_c),
      clock_max_abs_ppm_c => 5.0
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      next_second_i => (others => '0'),
      next_second_set_i => '0',
      
      tick_i => pps_tick_s,

      timestamp_o => rtc_slave_s
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
