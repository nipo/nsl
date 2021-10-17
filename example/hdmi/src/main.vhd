library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library work, nsl_color, nsl_io, nsl_clocking, unisim, nsl_data, nsl_hdmi, nsl_dvi, nsl_i2c, nsl_math, nsl_signal_generator;
use nsl_color.rgb.all;
use nsl_math.fixed.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_hdmi.hdmi.all;
    
entity main is
  generic (
    clock_i_hz_c : natural
    );
  port (
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    button_i : in std_ulogic_vector(0 to 3);
    switch_i : in std_ulogic_vector(0 to 1);
    led_o: out std_ulogic_vector(0 to 3);
    led4_o, led5_o: out rgb3;

    hdmi_i2c_o : out nsl_i2c.i2c.i2c_o;
    hdmi_i2c_i : in nsl_i2c.i2c.i2c_i;
    hdmi_clock_o : out nsl_io.diff.diff_pair;
    hdmi_data_o : out nsl_io.diff.diff_pair_vector(0 to 2);
    hdmi_cec_o: out nsl_io.io.opendrain;
    hdmi_cec_i: in std_ulogic;
    hdmi_hpd_i: in std_ulogic
    );
end entity;

architecture beh of main is
  
  -- Frame timings
  constant v_fp_c   : integer := 5;
  constant v_sync_c : integer := 5;
  constant v_bp_c   : integer := 20;
  constant v_act_c  : integer := 720;
  constant h_fp_c   : integer := 440;
  constant h_sync_c : integer := 40;
  constant h_bp_c   : integer := 220;
  constant h_act_c  : integer := 1280;
  constant hdmi_fps_c : real := 50.0;
  constant hdmi_audio_fs_c: integer := 48000;
  constant block_status_c: byte_string := from_hex("009900020000000000000000000000000000000000000000");

  -- Generate arbitrary pixel/serial clock by cascading MMCM and PLL.
  -- MMCM generates a pixel clock with any ratio (using fractional divisor)
  -- PLL does pixel clock x5 to get to serial clock.
  constant mmcm_vco_freq_c : real := 1.125e9;
  constant mmcm_ckin_div_c : integer := 2;
  -- Pixel clock, derived from timings above
  constant hdmi_pixel_clock_freq_c : real := real((v_fp_c + v_sync_c + v_bp_c + v_act_c)
                                                  * (h_fp_c + h_sync_c + h_bp_c + h_act_c))
                                                  * hdmi_fps_c;
  constant hdmi_serial_clock_freq_c : real := hdmi_pixel_clock_freq_c * 5.0;
  constant hdmi_pll_vco_mult_c : integer := integer(1600.0e6 / hdmi_serial_clock_freq_c);
  constant hdmi_pll_vco_freq_c : real := real(hdmi_pll_vco_mult_c) * hdmi_serial_clock_freq_c;
  constant hdmi_pll_ckin_div_c : integer := 1;

  -- HDMI Audio clock recovery packet parameters
  constant hdmi_audio_n_c : integer := 4096;
  constant hdmi_audio_cts_c : integer := integer(hdmi_pixel_clock_freq_c / (128.0 * real(hdmi_audio_fs_c)) * real(hdmi_audio_n_c));

  -- Translation to constants needed by components
  constant v_fp_m1_c   : unsigned(3-1 downto 0)  := to_unsigned(v_fp_c-1, 3);
  constant v_sync_m1_c : unsigned(3-1 downto 0)  := to_unsigned(v_sync_c-1, 3);
  constant v_bp_m1_c   : unsigned(5-1 downto 0)  := to_unsigned(v_bp_c-1, 5);
  constant v_act_m1_c  : unsigned(10-1 downto 0) := to_unsigned(v_act_c-1, 10);
  constant h_fp_m1_c   : unsigned(9-1 downto 0)  := to_unsigned(h_fp_c-1, 9);
  constant h_sync_m1_c : unsigned(6-1 downto 0)  := to_unsigned(h_sync_c-1, 6);
  constant h_bp_m1_c   : unsigned(8-1 downto 0)  := to_unsigned(h_bp_c-1, 8);
  constant h_act_m1_c  : unsigned(11-1 downto 0) := to_unsigned(h_act_c-1, 11);
  constant hdmi_audio_cts_u_c : unsigned(19 downto 0) := to_unsigned(hdmi_audio_cts_c, 20);

  constant audio_period_c : ufixed := to_ufixed(hdmi_pixel_clock_freq_c / real(hdmi_audio_fs_c), 12, -3);
  
  -- Interconnection
  signal blinker_s: unsigned(26 downto 0);

  signal hdmi_ref_clock_s, hdmi_pll_reset, hdmi_pll_feedback, hdmi_pixel_clock_reset_n_s : std_ulogic;
  signal hdmi_pixel_clock_s, hdmi_serial_clock_s : std_ulogic;
  signal hdmi_pixel_clock_unb_s, hdmi_serial_clock_unb_s : std_ulogic;
  signal pll_locked_s, pll_feedback_s, pll_reset_s: std_ulogic;

  signal block_user, block_status : std_ulogic_vector(0 to 191);
  signal audio_left_s, audio_right_s: unsigned(15 downto 0);

  signal tmds_s : nsl_dvi.dvi.symbol_vector_t;

  signal sol_s, sof_s, pixel_ready_s : std_ulogic;
  signal pixel_s : nsl_color.rgb.rgb24;

  signal di_valid_s : std_ulogic;
  signal di_ready_s : std_ulogic;
  signal di_s : data_island_t;

  signal audio_sample_tick_s : std_ulogic;
  signal audio_phase_acc : ufixed(-1 downto -12);
  signal audio_sample_xy_valid_s : std_ulogic;
  signal audio_sample_x_s, audio_sample_y_s : sfixed(15 downto 0);

  function phase_inc(freq: real) return ufixed
  is
    variable ret : ufixed(-1 downto -12) := to_ufixed(freq / real(hdmi_audio_fs_c), -1, -12);
  begin
    return ret;
  end function;

begin

  blinker_counter: process(clock_i, reset_n_i) is
  begin
    if reset_n_i = '0' then
      blinker_s <= (others => '0');
    elsif rising_edge(clock_i) then
      blinker_s <= blinker_s + 1;
    end if;
  end process;

  led_o <= std_ulogic_vector(blinker_s(blinker_s'left downto blinker_s'left-3));
  led4_o <= rgb3_green when hdmi_hpd_i = '1' else rgb3_red;
  led5_o <= rgb3_blue;

  pll_reset_s <= not reset_n_i;
  
  clock: unisim.vcomponents.mmcme2_base
    generic map (
      clkin1_period  => 1.0e9 / real(clock_i_hz_c),
      clkfbout_mult_f => mmcm_vco_freq_c / real(clock_i_hz_c / mmcm_ckin_div_c),
      clkout0_divide_f => mmcm_vco_freq_c / hdmi_pixel_clock_freq_c,
      divclk_divide  => mmcm_ckin_div_c
      )
    port map(
      rst      => pll_reset_s,
      pwrdwn   => '0',
      clkin1   => clock_i,
      clkfbin  => pll_feedback_s,
      clkfbout => pll_feedback_s,
      clkout0  => hdmi_ref_clock_s,
      locked   => pll_locked_s
      );

  hdmi_pll_reset <= not pll_locked_s;

  hdmi_clock_gen: unisim.vcomponents.plle2_base
    generic map (
      clkin1_period  => 1.0e9 / real(hdmi_pixel_clock_freq_c),
      clkfbout_mult  => hdmi_pll_vco_mult_c * 5 * hdmi_pll_ckin_div_c,
      clkout0_divide => integer(hdmi_pll_vco_freq_c / hdmi_serial_clock_freq_c),
      clkout1_divide => integer(hdmi_pll_vco_freq_c / hdmi_pixel_clock_freq_c),
      divclk_divide  => hdmi_pll_ckin_div_c
      )
    port map(
      rst      => hdmi_pll_reset,
      pwrdwn   => '0',
      clkin1   => hdmi_ref_clock_s,
      clkfbin  => hdmi_pll_feedback,
      clkfbout => hdmi_pll_feedback,
      clkout0  => hdmi_serial_clock_unb_s,
      clkout1  => hdmi_pixel_clock_unb_s,
      locked   => hdmi_pixel_clock_reset_n_s
      );

  serial_clockbuf: nsl_clocking.distribution.clock_buffer
    port map (
      clock_i => hdmi_serial_clock_unb_s,
      clock_o => hdmi_serial_clock_s
      );

  pixel_clockbuf: nsl_clocking.distribution.clock_buffer
    port map (
      clock_i => hdmi_pixel_clock_unb_s,
      clock_o => hdmi_pixel_clock_s
      );

  -- Generate a tick matching audio sample rate to gate audio samples (both
  -- HDMI out and sinus generators may work at full clock rate, we need some
  -- artificial rate limiter).
  audio_tick_gen: nsl_clocking.generator.tick_generator
    port map(
      reset_n_i => hdmi_pixel_clock_reset_n_s,
      clock_i => hdmi_pixel_clock_s,
      period_i => audio_period_c,
      tick_o => audio_sample_tick_s
      );

  driver: nsl_dvi.transceiver.dvi_driver
    port map(
      reset_n_i => hdmi_pixel_clock_reset_n_s,
      pixel_clock_i => hdmi_pixel_clock_s,
      serial_clock_i => hdmi_serial_clock_s,
      tmds_i => tmds_s,
      clock_o => hdmi_clock_o,
      data_o => hdmi_data_o
      );
  
  hdmi_audio_encoder: nsl_hdmi.audio.hdmi_spdif_di_encoder
    generic map(
      audio_clock_divisor_c => hdmi_audio_n_c
      )
    port map(
      reset_n_i => hdmi_pixel_clock_reset_n_s,
      clock_i => hdmi_pixel_clock_s,

      enable_i => '1',
      
      cts_i => hdmi_audio_cts_u_c,
      cts_send_i => sof_s,

      block_user_i => block_user,
      block_channel_status_i => block_status,
      block_channel_status_aesebu_auto_crc_i => '0',

      valid_i => audio_sample_tick_s,
      a_i.aux => "0000",
      a_i.audio(3 downto 0) => "0000",
      a_i.audio(19 downto 4) => audio_left_s,
      a_i.valid => '1',
      b_i.aux => "0000",
      b_i.audio(3 downto 0) => "0000",
      b_i.audio(19 downto 4) => audio_right_s,
      b_i.valid => '1',

      sof_i => sof_s,

      di_valid_o => di_valid_s,
      di_ready_i => di_ready_s,
      di_o => di_s
      );
  
   hdmi_encoder: nsl_hdmi.encoder.hdmi_13_encoder
     port map(
       reset_n_i => hdmi_pixel_clock_reset_n_s,
       pixel_clock_i => hdmi_pixel_clock_s,
  
       v_fp_m1_i => v_fp_m1_c,
       v_sync_m1_i => v_sync_m1_c,
       v_bp_m1_i => v_bp_m1_c,
       v_act_m1_i => v_act_m1_c,

       h_fp_m1_i => h_fp_m1_c,
       h_sync_m1_i => h_sync_m1_c,
       h_bp_m1_i => h_bp_m1_c,
       h_act_m1_i => h_act_m1_c,
  
       sof_o => sof_s,
       sol_o => sol_s,
       pixel_ready_o => pixel_ready_s,
       pixel_i => nsl_hdmi.hdmi.rgb24_pack(pixel_s),

       di_valid_i => di_valid_s,
       di_ready_o => di_ready_s,
       di_i => di_s,
  
       tmds_o => tmds_s
       );

  generator: nsl_dvi.pattern.color_bars
    port map(
      reset_n_i => hdmi_pixel_clock_reset_n_s,
      clock_i => hdmi_pixel_clock_s,

      sof_i => sof_s,
      sol_i => sol_s,
      pixel_ready_i => pixel_ready_s,
      pixel_o => pixel_s
      );
  
  block_user <= (others => '0');
  block_status <= bitswap(std_ulogic_vector(from_le(block_status_c)));
  
  audio_phase: process(hdmi_pixel_clock_s, hdmi_pixel_clock_reset_n_s) is
  begin
    if hdmi_pixel_clock_reset_n_s = '0' then
      audio_phase_acc <= (others => '0');
    elsif rising_edge(hdmi_pixel_clock_s) then
      if button_i(3) = '1' then
        audio_phase_acc <= audio_phase_acc + phase_inc(440.0);
      elsif button_i(2) = '1' then
        audio_phase_acc <= audio_phase_acc + phase_inc(440.0 * (2.0 ** (2.0/12.0)));
      elsif button_i(1) = '1' then
        audio_phase_acc <= audio_phase_acc + phase_inc(440.0 * (2.0 ** (4.0/12.0)));
      elsif button_i(0) = '1' then
        audio_phase_acc <= audio_phase_acc + phase_inc(440.0 * (2.0 ** (5.0/12.0)));
      end if;
    end if;
  end process;

  audio_samples: process(hdmi_pixel_clock_s) is
  begin
    if rising_edge(hdmi_pixel_clock_s) then
      if audio_sample_xy_valid_s = '1' then
        audio_left_s <= unsigned(audio_sample_x_s);
        audio_right_s <= unsigned(audio_sample_y_s);
      end if;
    end if;
  end process;

  sincos: nsl_signal_generator.trigonometry.rect_table
    generic map(
      scale_c => 2.0 ** 14
      )
    port map(
      clock_i => hdmi_pixel_clock_s,
      reset_n_i => hdmi_pixel_clock_reset_n_s,

      angle_i => audio_phase_acc,
      valid_i => audio_sample_tick_s,

      ready_i => '1',
      valid_o => audio_sample_xy_valid_s,
      x_o => audio_sample_x_s,
      y_o => audio_sample_y_s
      );
  
  hdmi_i2c_o.scl.drain_n <= '0';
  hdmi_i2c_o.sda.drain_n <= '0';

end architecture;
