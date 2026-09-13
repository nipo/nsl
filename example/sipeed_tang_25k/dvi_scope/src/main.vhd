library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work, nsl_color, nsl_clocking, nsl_data, nsl_dvi, nsl_video, nsl_math, nsl_digilent, nsl_sipeed, nsl_indication;
use nsl_color.rgb.all;
use nsl_data.text.all;
use nsl_digilent.pmod.all;
use nsl_dvi.terminal.all;
use nsl_indication.font.all;

-- Scope-style demo of the color-key overlay blender.
--
-- Two color-index pixel sources run in lockstep: a scope_renderer
-- underlay (graticule plus sine trace) and a terminal_labels_colormap
-- overlay (title bar and status line, blank cells emitting the key
-- color). dvi_blender_color_key merges them, a shared colormap lookup
-- turns the result into RGB for the DVI encoder.
--
-- Sliders: 0 runs the horizontal scroll, 1 enables the graticule, 2
-- halves the trace amplitude, 3 hides the overlay. Push buttons: 0/1
-- step the period count down/up, 2/3 pan the phase left/right. The
-- status line shows the period count, the phase origin in degrees and
-- the slider states.
entity main is
  generic (
    clock_i_hz_c : natural;
    -- Video mode, and the clocks it calls for.  Both are exact: the
    -- solver refuses a rate it cannot hold.
    mode_c : nsl_dvi.mode.mode_t
    );
  port (
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    switch_i : in std_ulogic_vector(0 to 3);
    button_i : in std_ulogic_vector(0 to 3);
    led_o: out std_ulogic_vector(0 to 1);

    pmod_dvi_o : out pmod_double_t
    );
end entity;

architecture beh of main is

  use nsl_dvi.mode.all;
  use nsl_clocking.pll.all;

  -- One stage reaches both clocks from the board oscillator.
  constant video_config_c : pll_config_t := pll_config(
    input_hz => clock_i_hz_c,
    o0 => pll_output(serial_clock_hz(mode_c)),
    o1 => pll_output(pixel_clock_hz(mode_c)));

  signal video_clock_s : std_ulogic_vector(0 to video_config_c.output_count-1);


  -- Interconnection
  signal blinker_s: unsigned(26 downto 0);

  signal dvi_ref_clock_s, dvi_pixel_clock_reset_n_s : std_ulogic;
  signal dvi_pixel_clock_s, dvi_serial_clock_s : std_ulogic;
  signal pll_locked_s : std_ulogic;

  signal tmds_s : nsl_dvi.dvi.symbol_vector_t;

  constant geometry_c : nsl_video.mode.geometry_t := nsl_video.mode.geometry(mode_c);
  constant pixel_config_c : nsl_video.pixel_stream.config_t
    := nsl_video.pixel_stream.config(pixels => 1);
  signal pixel_s : nsl_video.pixel_stream.bus_t;
  signal synced_s : std_ulogic;

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

  video_pll: nsl_clocking.pll.pll_multi
    generic map(
      config_c => video_config_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      clock_o => video_clock_s,
      locked_o => dvi_pixel_clock_reset_n_s
      );

  dvi_serial_clock_s <= video_clock_s(0);
  dvi_pixel_clock_s <= video_clock_s(1);

  driver: nsl_sipeed.pmod_dvi.pmod_dvi_output
    port map(
      reset_n_i => dvi_pixel_clock_reset_n_s,
      pixel_clock_i => dvi_pixel_clock_s,
      serial_clock_i => dvi_serial_clock_s,
      tmds_i => tmds_s,
      pmod_o => pmod_dvi_o
      );

  dvi_encoder: nsl_dvi.encoder.dvi_10_encoder
    generic map(
      config_c => pixel_config_c
      )
    port map(
      reset_n_i => dvi_pixel_clock_reset_n_s,
      pixel_clock_i => dvi_pixel_clock_s,

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

      tmds_o => tmds_s
      );

  scope: block is
    constant font_c: font_t := nsl_indication.font_6x8.font_6x8_c;
    constant font_hscale_c: natural := 2;
    constant font_vscale_c: natural := 2;
    constant cell_width_c : natural := font_width(font_c) * font_hscale_c;
    constant cell_height_c : natural := font_height(font_c) * font_vscale_c;
    constant row_count_l2_c : natural := nsl_math.arith.log2(mode_c.v.active / cell_height_c);
    constant column_count_l2_c : natural := nsl_math.arith.log2(mode_c.h.active / cell_width_c);
    constant status_row_c : natural := mode_c.v.active / cell_height_c - 1;

    constant color_count_l2_c : natural := 3;
    subtype color_t is unsigned(color_count_l2_c-1 downto 0);

    -- Colour indices run between the two generators, the blender and
    -- the lookup; only the lookup's output carries colour.
    constant index_config_c : nsl_video.pixel_stream.config_t
      := nsl_video.pixel_stream.config(pixels => 1,
                                       components => 1,
                                       component_bits => color_count_l2_c);

    -- Shared palette indices
    constant color_background_c : natural := 0;
    constant color_grid_c : natural := 1;
    constant color_trace_c : natural := 2;
    constant color_text_c : natural := 3;
    constant color_value_c : natural := 4;
    constant color_off_c : natural := 5;
    constant color_title_bg_c : natural := 6;
    constant color_key_c : natural := 7;

    constant palette_c : rgb24_vector(0 to 2**color_count_l2_c-1) := (
      color_background_c => rgb24_black,
      color_grid_c => (x"20", x"48", x"28"),
      color_trace_c => rgb24_lime,
      color_text_c => rgb24_white,
      color_value_c => rgb24_orange,
      color_off_c => rgb24_dim_gray,
      color_title_bg_c => rgb24_navy,
      -- Key entry, only ever visible if blending is broken
      color_key_c => rgb24_magenta
      );

    -- Label color slots, resolved through colors_s
    constant lc_blank_c : natural := 0;
    constant lc_title_fg_c : natural := 1;
    constant lc_title_bg_c : natural := 2;
    constant lc_text_c : natural := 3;
    constant lc_value_c : natural := 4;
    constant lc_scroll_c : natural := 5;
    constant lc_grid_c : natural := 6;
    constant lc_zoom_c : natural := 7;

    constant title_text_c : string := " NSL SCOPE - KEYED OVERLAY ";
    constant periods_label_c : string := "PERIODS ";
    constant periods_value_length_c : natural := 5;
    constant phase_label_c : string := "PHASE ";
    constant phase_value_length_c : natural := 3;
    constant scroll_text_c : string := "SCROLL";
    constant grid_text_c : string := "GRID";
    constant zoom_text_c : string := "ZOOM";

    constant labels_c : label_vector(0 to 7) := (
      text_label(0, 0, title_text_c'length, lc_title_fg_c, lc_title_bg_c),
      text_label(status_row_c, 1, periods_label_c'length, lc_text_c, lc_blank_c),
      text_label(status_row_c, 9, periods_value_length_c, lc_value_c, lc_blank_c),
      text_label(status_row_c, 16, phase_label_c'length, lc_text_c, lc_blank_c),
      text_label(status_row_c, 22, phase_value_length_c, lc_value_c, lc_blank_c),
      text_label(status_row_c, 28, scroll_text_c'length, lc_scroll_c, lc_blank_c),
      text_label(status_row_c, 36, grid_text_c'length, lc_grid_c, lc_blank_c),
      text_label(status_row_c, 42, zoom_text_c'length, lc_zoom_c, lc_blank_c)
      );

    signal text_s : string(1 to labels_text_length(labels_c));
    signal periods_text_s : string(1 to periods_value_length_c);
    signal phase_text_s : string(1 to phase_value_length_c);
    signal base_colors_s, colors_s : label_color_vector(0 to labels_color_count(labels_c, lc_blank_c)-1);

    signal sw_sync_s : std_ulogic_vector(0 to 3);
    signal button_sync_s : std_ulogic_vector(0 to 3);
    signal phase_increment_s, phase_origin_s : unsigned(15 downto 0);
    signal phase_angle_s : unsigned(8 downto 0);

    signal under_s, over_s, blend_s : nsl_video.pixel_stream.bus_t;
    signal frame_end_s : std_ulogic;
  begin

    sw_sync: nsl_clocking.async.async_sampler
      generic map(
        cycle_count_c => 2,
        data_width_c => 4
        )
      port map(
        clock_i => dvi_pixel_clock_s,
        data_i => switch_i,
        data_o => sw_sync_s
        );

    buttons: for i in 0 to 3 generate
      debounce: nsl_clocking.async.async_input
        generic map(
          debounce_count_c => 65536
          )
        port map(
          clock_i => dvi_pixel_clock_s,
          reset_n_i => dvi_pixel_clock_reset_n_s,
          data_i => button_i(i),
          data_o => button_sync_s(i)
          );
    end generate;

    controls: work.top.scope_controls
      port map(
        clock_i => dvi_pixel_clock_s,
        reset_n_i => dvi_pixel_clock_reset_n_s,

        tick_i => frame_end_s,

        run_i => sw_sync_s(0),
        freq_down_i => button_sync_s(0),
        freq_up_i => button_sync_s(1),
        pan_left_i => button_sync_s(2),
        pan_right_i => button_sync_s(3),

        phase_increment_o => phase_increment_s,
        phase_origin_o => phase_origin_s,
        periods_text_o => periods_text_s,
        phase_angle_o => phase_angle_s
        );

    phase_text_s <= to_decimal_string(phase_angle_s, 3);

    text_s <= title_text_c & periods_label_c & periods_text_s
              & phase_label_c & phase_text_s
              & scroll_text_c & grid_text_c & zoom_text_c;

    base_colors_s(lc_blank_c) <= to_unsigned(color_key_c, 8);
    base_colors_s(lc_title_fg_c) <= to_unsigned(color_text_c, 8);
    base_colors_s(lc_title_bg_c) <= to_unsigned(color_title_bg_c, 8);
    base_colors_s(lc_text_c) <= to_unsigned(color_text_c, 8);
    base_colors_s(lc_value_c) <= to_unsigned(color_value_c, 8);
    base_colors_s(lc_scroll_c) <= to_unsigned(color_trace_c, 8) when sw_sync_s(0) = '1'
                                  else to_unsigned(color_off_c, 8);
    base_colors_s(lc_grid_c) <= to_unsigned(color_text_c, 8) when sw_sync_s(1) = '1'
                                else to_unsigned(color_off_c, 8);
    base_colors_s(lc_zoom_c) <= to_unsigned(color_text_c, 8) when sw_sync_s(2) = '1'
                                else to_unsigned(color_off_c, 8);

    -- Hiding the overlay is only a matter of coloring every cell with
    -- the key
    overlay_hide: for i in 0 to labels_color_count(labels_c, lc_blank_c)-1 generate
      colors_s(i) <= base_colors_s(i) when sw_sync_s(3) = '0'
                     else to_unsigned(color_key_c, 8);
    end generate;

    frame_end_s <= '1' when nsl_video.pixel_stream.is_taken(pixel_config_c, pixel_s.m, pixel_s.s)
                   and nsl_video.pixel_stream.is_eof(pixel_config_c, pixel_s.m)
                   else '0';

    underlay: work.top.scope_renderer
      generic map(
        geometry_c => geometry_c,
        config_c => index_config_c,
        color_count_l2_c => color_count_l2_c,
        background_color_c => color_background_c,
        grid_color_c => color_grid_c,
        trace_color_c => color_trace_c,
        trace_amplitude_c => 300
        )
      port map(
        clock_i => dvi_pixel_clock_s,
        reset_n_i => dvi_pixel_clock_reset_n_s,

        out_o => under_s.m,
        out_i => under_s.s,

        phase_increment_i => phase_increment_s,
        phase_origin_i => phase_origin_s,
        zoom_i => sw_sync_s(2),
        grid_enable_i => sw_sync_s(1)
        );

    overlay: nsl_dvi.terminal.terminal_labels_colormap
      generic map(
        row_count_l2_c => row_count_l2_c,
        column_count_l2_c => column_count_l2_c,
        character_count_l2_c => 8,
        color_count_l2_c => color_count_l2_c,
        font_c => font_c,
        labels_c => labels_c,
        blank_color_c => lc_blank_c,
        font_hscale_c => font_hscale_c,
        font_vscale_c => font_vscale_c,
        config_c => index_config_c,
        geometry_c => geometry_c
        )
      port map(
        clock_i => dvi_pixel_clock_s,
        reset_n_i => dvi_pixel_clock_reset_n_s,

        out_o => over_s.m,
        out_i => over_s.s,

        text_i => text_s,
        color_i => colors_s
        );

    blender: nsl_dvi.blender.dvi_blender_color_key
      generic map(
        config_c => index_config_c,
        key_color_c => color_key_c
        )
      port map(
        overlay_i => over_s.m,
        overlay_o => over_s.s,

        underlay_i => under_s.m,
        underlay_o => under_s.s,

        out_o => blend_s.m,
        out_i => blend_s.s
        );

    lookup: nsl_dvi.colormap.dvi_colormap_lookup
      generic map(
        in_config_c => index_config_c,
        out_config_c => pixel_config_c
        )
      port map(
        clock_i => dvi_pixel_clock_s,
        reset_n_i => dvi_pixel_clock_reset_n_s,

        palette_i => palette_c,

        in_i => blend_s.m,
        in_o => blend_s.s,

        out_o => pixel_s.m,
        out_i => pixel_s.s
        );

  end block;

end architecture;
