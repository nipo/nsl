library ieee;
use ieee.std_logic_1164.all;

entity tb is
end tb;

library nsl_clocking;
use nsl_clocking.async.all;

architecture arch of tb is

  constant internal_clock_freq : integer := 48000000;
  constant internal_clock_off_ppm : integer := -100000;
  constant reference_clock_freq : integer := 12000000;
  constant reference_clock_off_ppm : integer := 10;
  constant output_clock_freq : integer := 12000000;

  signal internal_clock : std_ulogic;
  signal reference_clock : std_ulogic;
  signal internal_reset_n : std_ulogic;
  signal reference_tick, output_tick : std_ulogic;

  constant internal_clock_half_period : time := 1000 ps * (1000000 + internal_clock_off_ppm) / (internal_clock_freq / 1000) / 2;
  constant reference_clock_half_period : time := 1000 ps * (1000000 + reference_clock_off_ppm) / (reference_clock_freq / 1000) / 2;
  constant output_clock_half_period : time := 1000000000 ps / (output_clock_freq / 1000) / 2;

begin

  internal_clock_gen: process
  begin
    while true
    loop
      internal_clock <= '0';
      wait for internal_clock_half_period;
      internal_clock <= '1';
      wait for internal_clock_half_period;
    end loop;
  end process;

  internal_reset_gen: process
  begin
    internal_reset_n <= '0';
    wait for internal_clock_half_period * 3 / 2;
    internal_reset_n <= '1';
    wait;
  end process;

  reference_clock_gen: process
  begin
    while true
    loop
      reference_clock <= '0';
      wait for reference_clock_half_period;
      reference_clock <= '1';
      wait for reference_clock_half_period;
    end loop;
  end process;

  reference_sampler: nsl_clocking.async.async_input
    generic map(
      debounce_count_c => 1
      )
    port map(
      clock_i => internal_clock,
      reset_n_i => internal_reset_n,
      data_i => reference_clock,
      rising_o => reference_tick
      );
  
  recoverer: nsl_clocking.async.async_recovery
    generic map(
      clock_i_hz_c => internal_clock_freq,
      tick_skip_max_c => 3,
      tick_i_hz_c => reference_clock_freq,
      tick_o_hz_c => output_clock_freq,
      target_ppm_c => 400
      )
    port map(
      clock_i => internal_clock,
      reset_n_i => internal_reset_n,

      tick_i => reference_tick,
      tick_o => output_tick
      );

  
  
end;
