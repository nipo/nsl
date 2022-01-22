library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity tb is
end tb;

library nsl_sdr, nsl_math, nsl_simulation, nsl_signal_generator;
use nsl_math.fixed.all;

architecture arch of tb is

  constant fs : integer := 240e6;
  constant internal_clock_freq : integer := 240e6;
  constant symbol_per_s : integer := 1e6;

  signal s_clock : std_ulogic;
  signal s_reset_n : std_ulogic;

  signal s_channel: unsigned(5 downto 0);
  signal s_mi: unsigned(0 downto 0);
  signal s_box_freq, s_rc_freq, s_center_freq : ufixed(-1 downto -16);
  signal s_box_freq_r, s_rc_freq_r, s_center_freq_r : real;
  signal s_done : std_ulogic_vector(0 to 0);
  signal s_box_v, s_rc_v : std_ulogic;

begin

  box_conv: process(s_box_freq) is
  begin
    s_box_freq_r <= to_real(s_box_freq) * real(fs);
  end process;

  rc_conv: process(s_rc_freq) is
  begin
    s_rc_freq_r <= to_real(s_rc_freq) * real(fs);
  end process;

  center_conv: process(s_center_freq) is
  begin
    s_center_freq_r <= to_real(s_center_freq) * real(fs);
  end process;

  s_box_v <= '1' when abs(s_box_freq_r - s_center_freq_r) <= 400.0e3 and abs(s_box_freq_r - s_center_freq_r) >= 185.0e3 else '0';
  s_rc_v <= '1' when abs(s_rc_freq_r - s_center_freq_r) <= 400.0e3 and abs(s_rc_freq_r - s_center_freq_r) >= 185.0e3 else '0';
  
  st: process
  begin
    s_done <= "0";

    s_channel <= to_unsigned(0, 6);
    s_mi <= "0"; wait for 1 us;

    wait for 10 us;
    
    s_mi <= "0"; wait for 1 us;
    s_mi <= "0"; wait for 1 us;
    s_mi <= "1"; wait for 1 us;
    s_mi <= "0"; wait for 1 us;
    s_mi <= "1"; wait for 1 us;
    s_mi <= "0"; wait for 1 us;
    s_mi <= "1"; wait for 1 us;
    s_mi <= "0"; wait for 1 us;
    s_mi <= "1"; wait for 1 us;
    s_mi <= "1"; wait for 1 us;
    s_mi <= "0"; wait for 1 us;
    s_mi <= "0"; wait for 1 us;
    s_mi <= "1"; wait for 1 us;
    s_mi <= "1"; wait for 1 us;
    s_mi <= "0"; wait for 1 us;
    s_mi <= "0"; wait for 1 us;
    s_mi <= "1"; wait for 1 us;
    s_mi <= "1"; wait for 1 us;
    s_mi <= "1"; wait for 1 us;
    s_mi <= "0"; wait for 1 us;
    s_mi <= "0"; wait for 1 us;
    s_mi <= "0"; wait for 1 us;
    s_mi <= "1"; wait for 1 us;
    s_mi <= "1"; wait for 1 us;
    s_mi <= "1"; wait for 1 us;
    s_mi <= "0"; wait for 1 us;
    s_mi <= "0"; wait for 1 us;
    s_mi <= "0"; wait for 1 us;
    s_mi <= "0"; wait for 1 us;
    s_mi <= "1"; wait for 1 us;
    s_mi <= "0"; wait for 1 us;
    s_mi <= "1"; wait for 1 us;

    wait for 2 us;
      
    s_done <= "1";
    wait;
  end process;

  fgrc: nsl_sdr.gfsk.gfsk_frequency_plan
    generic map(
      fs_c => real(fs),
      clock_i_hz_c => internal_clock_freq,
      channel_count_c => 40,
      channel_0_center_hz_c => 22.0e6,
      channel_separation_hz_c => 2.0e6,
      symbol_rate_c => real(symbol_per_s),
      bt_c => 0.5,
      gfsk_method_c => "rc"
      )
    port map(
      clock_i => s_clock,
      reset_n_i => s_reset_n,

      channel_i => s_channel,
      symbol_i => s_mi,
      phase_increment_o => s_rc_freq
      );

  fgbox: nsl_sdr.gfsk.gfsk_frequency_plan
    generic map(
      fs_c => real(fs),
      clock_i_hz_c => internal_clock_freq,
      channel_count_c => 40,
      channel_0_center_hz_c => 22.0e6,
      channel_separation_hz_c => 2.0e6,
      symbol_rate_c => real(symbol_per_s),
      bt_c => 0.5,
      gfsk_method_c => "box"
      )
    port map(
      clock_i => s_clock,
      reset_n_i => s_reset_n,

      channel_i => s_channel,
      symbol_i => s_mi,
      phase_increment_o => s_box_freq
      );

  cf: nsl_sdr.fsk.fsk_frequency_plan
    generic map(
      fs_c => real(fs),
      channel_count_c => 40,
      channel_0_center_hz_c => 22.0e6,
      channel_separation_hz_c => 2.0e6,
      fd_0_hz_c => 0.0,
      fd_separation_hz_c => 0.0
      )
    port map(
      clock_i => s_clock,
      reset_n_i => s_reset_n,

      channel_i => s_channel,
      symbol_i => s_mi,
      phase_increment_o => s_center_freq
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
