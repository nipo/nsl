library ieee;
use ieee.std_logic_1164.all;

entity tb is
end tb;

library nsl_clocking;
use nsl_clocking.pll.all;

architecture arch of tb is

  constant internal_clock_freq : integer := 10000000;

  function freq_half_period(freq, error_ppm: integer)
    return time
  is
    constant period : time := 1000 ps * (1000000 + error_ppm) / (freq / 1000);
  begin
    return period / 2;
  end function;

  signal internal_clock, internal_reset_n, pll_out, pll_locked : std_ulogic;
  
begin

  clock_gen: process
    variable half_period : time;
  begin
    half_period := freq_half_period(internal_clock_freq, 0);

    internal_reset_n <= '0';

    internal_clock <= '0';
    wait for half_period;
    internal_clock <= '1';
    wait for half_period;

    internal_reset_n <= '1';

    internal_clock <= '0';
    wait for half_period;
    internal_clock <= '1';
    wait for half_period;

    -- Test input range
    for error_ppm in -200 to 42200
    loop
      half_period := freq_half_period(internal_clock_freq, error_ppm);

      for cycle in 0 to 10
      loop
        internal_clock <= '0';
        wait for half_period;
        internal_clock <= '1';
        wait for half_period;
      end loop;
    end loop;

    wait for 1 ms;

    -- Test breaking the input clock
    half_period := freq_half_period(internal_clock_freq, 0);

    for cycle in 0 to 10000
    loop
      internal_clock <= '0';
      wait for half_period;
      internal_clock <= '1';
      wait for half_period;
    end loop;

    wait for 1 ms;

    for cycle in 0 to 10000
    loop
      internal_clock <= '0';
      wait for half_period;
      internal_clock <= '1';
      wait for half_period;
    end loop;


    -- Reset while running
    half_period := freq_half_period(internal_clock_freq, -100);

    for cycle in 0 to 10000
    loop
      internal_clock <= '0';
      wait for half_period;
      internal_clock <= '1';
      wait for half_period;
    end loop;
    
    internal_reset_n <= '0';

    internal_clock <= '0';
    wait for half_period;
    internal_clock <= '1';
    wait for half_period;

    internal_reset_n <= '1';

    internal_clock <= '0';
    wait for half_period;
    internal_clock <= '1';
    wait for half_period;

    for cycle in 0 to 10000
    loop
      internal_clock <= '0';
      wait for half_period;
      internal_clock <= '1';
      wait for half_period;
    end loop;

    wait;
  end process;
  
  pll: nsl_clocking.pll.pll_basic
    generic map(
      input_hz_c => internal_clock_freq,
      output_hz_c => 80000000
      )
    port map(
      clock_i => internal_clock,
      reset_n_i => internal_reset_n,

      clock_o => pll_out,
      locked_o => pll_locked
      );

  
  
end;
