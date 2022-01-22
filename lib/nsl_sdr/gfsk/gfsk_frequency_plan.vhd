library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math, nsl_dsp, nsl_sdr;
use nsl_math.fixed.all;

entity gfsk_frequency_plan is
  generic (
    fs_c : real;
    clock_i_hz_c : integer;
    channel_0_center_hz_c : real;
    channel_separation_hz_c : real;
    channel_count_c : integer;
    symbol_rate_c : real;
    bt_c : real;
    gfsk_method_c : string := "box"
    );
  port (
    clock_i: in std_ulogic;
    reset_n_i : in std_ulogic;

    channel_i : in unsigned(nsl_math.arith.log2(channel_count_c)-1 downto 0);
    symbol_i : in unsigned;

    phase_increment_o : out ufixed
    );
end entity;    

architecture beh of gfsk_frequency_plan is

  signal s_fsk_phase_inc : ufixed(phase_increment_o'left downto phase_increment_o'right);
  
begin

  fp: nsl_sdr.fsk.fsk_frequency_plan
    generic map(
      fs_c => fs_c,
      channel_0_center_hz_c => channel_0_center_hz_c,
      channel_separation_hz_c => channel_separation_hz_c,
      channel_count_c => channel_count_c,
      fd_0_hz_c => - symbol_rate_c * bt_c / 2.0,
      fd_separation_hz_c => symbol_rate_c * bt_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      channel_i => channel_i,
      symbol_i => symbol_i,
      phase_increment_o => s_fsk_phase_inc
      );

  gaussian: nsl_dsp.gaussian.gaussian_ufixed
    generic map(
      symbol_sample_count_c => integer(real(clock_i_hz_c) / symbol_rate_c),
      bt_c => bt_c,
      approximation_method_c => gfsk_method_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      in_i => s_fsk_phase_inc,
      out_o => phase_increment_o
      );
  
end architecture;

