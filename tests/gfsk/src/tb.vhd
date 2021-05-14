library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb is
end tb;

library nsl_sdr, nsl_math, nsl_simulation, nsl_signal_generator;
use nsl_math.fixed.all;

architecture arch of tb is

  constant internal_clock_freq : integer := 240000000;
  constant symbol_per_s : integer := 1000000;

  signal s_clock : std_ulogic;
  signal s_reset_n : std_ulogic;

  signal s_channel: unsigned(5 downto 0);
  signal s_mi: unsigned(0 downto 0);
  signal s_mi_r_f : ufixed(-1 downto -16);
  signal s_mi_r_r : real;
  signal s_freq_r : real;
  signal s_value : sfixed(0 downto -10);
  signal s_value_r : real;
  signal s_done : std_ulogic_vector(0 to 0);

begin

  a: process(s_mi_r_f) is
    variable tmp: real;
  begin
    tmp := to_real(s_mi_r_f);

    s_mi_r_r <= tmp;
    s_freq_r <= tmp * real(internal_clock_freq);
  end process;

  s_value_r <= to_real(s_value);

  st: process
  begin
    s_done <= "0";

    for chan in 0 to 39
    loop
      for re in 0 to 8
      loop
        for mi in 0 to 1
        loop
          s_channel <= to_unsigned(chan, 6);
          s_mi <= to_unsigned(mi, 1);
          wait for 1 us;
        end loop;
      end loop;
    end loop;

    wait for 2 us;
      
    s_done <= "1";
    wait;
  end process;

  fg: nsl_sdr.gfsk.gfsk_frequency_plan
    generic map(
      fs_c => real(internal_clock_freq),
      channel_count_c => 40,
      channel_0_center_hz_c => 100.0e6,
      channel_separation_hz_c => -2.0e6,
      fd_0_hz_c => 500.0e3,
      fd_separation_hz_c => -1.0e6,
      symbol_rate_c => real(symbol_per_s),
      bt_c => 0.5
      )
    port map(
      clock_i => s_clock,
      reset_n_i => s_reset_n,

      channel_i => s_channel,
      symbol_i => s_mi,
      phase_increment_o => s_mi_r_f
      );

  nco: nsl_signal_generator.nco.nco_sinus
    generic map(
      trim_bits_c => 10
      )
    port map(
      clock_i => s_clock,
      reset_n_i => s_reset_n,
      angle_increment_i => s_mi_r_f,
      value_o => s_value
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
