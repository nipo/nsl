library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library work, nsl_color, nsl_io, nsl_clocking, nsl_data, nsl_hdmi, nsl_dvi, nsl_video, nsl_math, nsl_signal_generator, nsl_event, nsl_digilent, nsl_sipeed;
use nsl_color.rgb.all;
use nsl_digilent.pmod.all;
use nsl_math.fixed.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_hdmi.hdmi.all;
    
entity main is
  generic (
    clock_i_hz_c : natural;
    -- Video mode, and the clocks it calls for.  Both are exact: the
    -- solver refuses a rate it cannot hold.
    mode_c : nsl_video.mode.mode_t
    );
  port (
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    button_i : in std_ulogic_vector(0 to 3);
    led_o: out std_ulogic_vector(0 to 1);

    pmod_dvi_o : out pmod_double_t
    );
end entity;

architecture beh of main is

  use nsl_video.mode.all;
  use nsl_clocking.pll.all;

  -- 720p50 needs 74.25MHz, which no single ratio reaches from 50MHz:
  -- the phase detector floor leaves the input divider at 1 or 2, and
  -- neither 50MHz nor 25MHz times a whole number lands on a multiple
  -- of 74.25MHz inside the VCO window.  Two stages do reach it: the
  -- first gets to 562.5MHz, from where the second can divide by 25
  -- and still stay above the floor.  This intermediate rate is
  -- chosen for this mode; another mode may want another one, or none
  -- at all.
  constant intermediate_hz_c : natural := 562500000;

  -- The second PLL takes this straight from the first one: the
  -- global clock network does not carry a rate this far above what
  -- fabric clocks run at, and a PLL reference does not need it to.
  constant ref_config_c : pll_config_t := pll_config(
    input_hz => clock_i_hz_c,
    o0 => pll_output(intermediate_hz_c,
                     routing => nsl_clocking.pll_backend.pll_routing_id("NONE")));

  constant video_config_c : pll_config_t := pll_config(
    input_hz => intermediate_hz_c,
    o0 => pll_output(serial_clock_hz(mode_c)),
    o1 => pll_output(pixel_clock_hz(mode_c)));

  signal video_clock_s : std_ulogic_vector(0 to video_config_c.output_count-1);
  
  constant hdmi_audio_fs_c: integer := 48000;
  constant block_status_c: byte_string := from_hex("009900020000000000000000000000000000000000000000");


  -- HDMI Audio clock recovery packet parameters
  constant hdmi_audio_n_c : integer := 4096;
  constant hdmi_audio_cts_c : integer := integer(pixel_clock(mode_c) / (128.0 * real(hdmi_audio_fs_c)) * real(hdmi_audio_n_c));
  constant hdmi_audio_cts_u_c : unsigned(19 downto 0) := to_unsigned(hdmi_audio_cts_c, 20);

  constant audio_period_c : ufixed := to_ufixed(pixel_clock(mode_c) / real(hdmi_audio_fs_c), 12, -3);
  
  -- Interconnection
  signal blinker_s: unsigned(26 downto 0);

  signal hdmi_ref_clock_s, hdmi_pixel_clock_reset_n_s : std_ulogic;
  signal hdmi_pixel_clock_s, hdmi_serial_clock_s : std_ulogic;
  signal pll_locked_s : std_ulogic;

  signal block_user, block_status : std_ulogic_vector(0 to 191);
  signal audio_left_s, audio_right_s: unsigned(15 downto 0);

  signal tmds_s : nsl_dvi.dvi.symbol_vector_t;

  constant geometry_c : nsl_video.mode.geometry_t := nsl_video.mode.geometry(mode_c);
  constant pixel_config_c : nsl_video.pixel_stream.config_t
    := nsl_video.pixel_stream.config(pixels => 1);

  signal pixel_s : nsl_video.pixel_stream.bus_t;
  signal synced_s, frame_end_s : std_ulogic;

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

  led_o <= std_ulogic_vector(blinker_s(blinker_s'left downto blinker_s'left-1));

  ref_pll: nsl_clocking.pll.pll_multi
    generic map(
      config_c => ref_config_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      clock_o(0) => hdmi_ref_clock_s,
      locked_o => pll_locked_s
      );

  video_pll: nsl_clocking.pll.pll_multi
    generic map(
      config_c => video_config_c
      )
    port map(
      clock_i => hdmi_ref_clock_s,
      reset_n_i => pll_locked_s,
      clock_o => video_clock_s,
      locked_o => hdmi_pixel_clock_reset_n_s
      );

  hdmi_serial_clock_s <= video_clock_s(0);
  hdmi_pixel_clock_s <= video_clock_s(1);

  -- Generate a tick matching audio sample rate to gate audio samples (both
  -- HDMI out and sinus generators may work at full clock rate, we need some
  -- artificial rate limiter).
  audio_tick_gen: nsl_event.tick.tick_generator
    port map(
      reset_n_i => hdmi_pixel_clock_reset_n_s,
      clock_i => hdmi_pixel_clock_s,
      period_i => audio_period_c,
      tick_o => audio_sample_tick_s
      );

  driver: nsl_sipeed.pmod_dvi.pmod_dvi_output
    port map(
      reset_n_i => hdmi_pixel_clock_reset_n_s,
      pixel_clock_i => hdmi_pixel_clock_s,
      serial_clock_i => hdmi_serial_clock_s,
      tmds_i => tmds_s,
      pmod_o => pmod_dvi_o
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
      cts_send_i => frame_end_s,

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

      sof_i => frame_end_s,

      di_valid_o => di_valid_s,
      di_ready_i => di_ready_s,
      di_o => di_s
      );
  
   hdmi_encoder: nsl_hdmi.encoder.hdmi_13_encoder
     generic map(
       config_c => pixel_config_c
       )
     port map(
       reset_n_i => hdmi_pixel_clock_reset_n_s,
       pixel_clock_i => hdmi_pixel_clock_s,
  
       v_fp_m1_i => v_fp_m1(mode_c),
       v_sync_m1_i => v_sync_m1(mode_c),
       v_bp_m1_i => v_bp_m1(mode_c),
       v_act_m1_i => v_act_m1(mode_c),

       h_fp_m1_i => h_fp_m1(mode_c),
       h_sync_m1_i => h_sync_m1(mode_c),
       h_bp_m1_i => h_bp_m1(mode_c),
       h_act_m1_i => h_act_m1(mode_c),

       vsync_i => mode_c.v.sync,
       hsync_i => mode_c.h.sync,
  
       pixel_i => pixel_s.m,
       pixel_o => pixel_s.s,
       synced_o => synced_s,

       di_valid_i => di_valid_s,
       di_ready_o => di_ready_s,
       di_i => di_s,
  
       tmds_o => tmds_s
       );

  -- What a frame boundary looks like from beside the stream
  frame_end_s <= '1' when nsl_video.pixel_stream.is_taken(pixel_config_c, pixel_s.m, pixel_s.s)
                 and nsl_video.pixel_stream.is_eof(pixel_config_c, pixel_s.m)
                 else '0';

  generator: nsl_video.pattern.rgb_color_bars
    generic map(
      geometry_c => geometry_c,
      config_c => pixel_config_c
      )
    port map(
      reset_n_i => hdmi_pixel_clock_reset_n_s,
      clock_i => hdmi_pixel_clock_s,

      out_o => pixel_s.m,
      out_i => pixel_s.s
      );
  
  block_user <= (others => '0');
  block_status <= bitswap(std_ulogic_vector(from_le(block_status_c)));
  
  audio_phase: process(hdmi_pixel_clock_s, hdmi_pixel_clock_reset_n_s) is
  begin
    if hdmi_pixel_clock_reset_n_s = '0' then
      audio_phase_acc <= (others => '0');
    elsif rising_edge(hdmi_pixel_clock_s) then
      if audio_sample_tick_s = '1' then
        if button_i(0) = '1' then
          audio_phase_acc <= audio_phase_acc + phase_inc(440.0 * (2.0 ** (0.0/12.0)));
        elsif button_i(1) = '1' then
          audio_phase_acc <= audio_phase_acc + phase_inc(440.0 * (2.0 ** (2.0/12.0)));
        elsif button_i(2) = '1' then
          audio_phase_acc <= audio_phase_acc + phase_inc(440.0 * (2.0 ** (4.0/12.0)));
        elsif button_i(3) = '1' then
          audio_phase_acc <= audio_phase_acc + phase_inc(440.0 * (2.0 ** (5.0/12.0)));
        end if;
      end if;
    end if;
  end process;

  audio_samples: process(hdmi_pixel_clock_s) is
  begin
    if rising_edge(hdmi_pixel_clock_s) then
      if audio_sample_xy_valid_s = '1' then
        audio_left_s <= shift_right(unsigned(audio_sample_x_s), 8);
        audio_right_s <= shift_right(unsigned(audio_sample_y_s), 8);
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

end architecture;
