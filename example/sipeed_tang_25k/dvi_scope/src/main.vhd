library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work, nsl_color, nsl_clocking, nsl_data, nsl_dvi, nsl_math, nsl_digilent, nsl_sipeed, nsl_indication;
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
    clock_i_hz_c : natural
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

  -- Frame timings, XGA 1024x768 at 60Hz, 65MHz pixel clock, both
  -- syncs active low.
  constant v_fp_c   : integer := 3;
  constant v_sync_c : integer := 6;
  constant v_bp_c   : integer := 29;
  constant v_act_c  : integer := 768;
  constant h_fp_c   : integer := 24;
  constant h_sync_c : integer := 136;
  constant h_bp_c   : integer := 160;
  constant h_act_c  : integer := 1024;

  -- The matching clocks are set inside the PLL wrappers:
  -- stage1_pll: 50 MHz / 2 * 40 / 2 = 500 MHz reference,
  -- dvi_pll: 500 MHz / 20 * 52 = 1300 MHz VCO, / 4 = 325 MHz serial
  -- clock, / 20 = 65 MHz pixel clock.

  -- Translation to constants needed by components
  constant v_fp_m1_c   : unsigned(2-1 downto 0)  := to_unsigned(v_fp_c-1, 2);
  constant v_sync_m1_c : unsigned(3-1 downto 0)  := to_unsigned(v_sync_c-1, 3);
  constant v_bp_m1_c   : unsigned(5-1 downto 0)  := to_unsigned(v_bp_c-1, 5);
  constant v_act_m1_c  : unsigned(10-1 downto 0) := to_unsigned(v_act_c-1, 10);
  constant h_fp_m1_c   : unsigned(5-1 downto 0)  := to_unsigned(h_fp_c-1, 5);
  constant h_sync_m1_c : unsigned(8-1 downto 0)  := to_unsigned(h_sync_c-1, 8);
  constant h_bp_m1_c   : unsigned(8-1 downto 0)  := to_unsigned(h_bp_c-1, 8);
  constant h_act_m1_c  : unsigned(10-1 downto 0) := to_unsigned(h_act_c-1, 10);

  -- Interconnection
  signal blinker_s: unsigned(26 downto 0);

  signal dvi_ref_clock_s, dvi_pll_reset, dvi_pixel_clock_reset_n_s : std_ulogic;
  signal dvi_pixel_clock_s, dvi_serial_clock_s : std_ulogic;
  signal dvi_pixel_clock_unb_s, dvi_serial_clock_unb_s : std_ulogic;
  signal pll_locked_s, pll_reset_s: std_ulogic;

  signal tmds_s : nsl_dvi.dvi.symbol_vector_t;

  signal sol_s, sof_s, pixel_ready_s, pixel_valid_s : std_ulogic;
  signal pixel_s : nsl_color.rgb.rgb24;

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

  pll_reset_s <= not reset_n_i;

  clock: work.top.stage1_pll
    port map(
      clkin => clock_i,
      clkout0 => dvi_ref_clock_s,
      mdclk => clock_i,
      reset => pll_reset_s,
      lock => pll_locked_s
      );

  dvi_pll_reset <= not pll_locked_s;

  dvi_clock_gen: work.top.dvi_pll
    port map(
      reset    => dvi_pll_reset,
      clkin    => dvi_ref_clock_s,
      clkout0  => dvi_serial_clock_unb_s,
      clkout1  => dvi_pixel_clock_unb_s,
      lock     => dvi_pixel_clock_reset_n_s,
      mdclk    => clock_i
      );

  serial_clockbuf: nsl_clocking.distribution.clock_buffer
    port map (
      clock_i => dvi_serial_clock_unb_s,
      clock_o => dvi_serial_clock_s
      );

  pixel_clockbuf: nsl_clocking.distribution.clock_buffer
    port map (
      clock_i => dvi_pixel_clock_unb_s,
      clock_o => dvi_pixel_clock_s
      );

  driver: nsl_sipeed.pmod_dvi.pmod_dvi_output
    port map(
      reset_n_i => dvi_pixel_clock_reset_n_s,
      pixel_clock_i => dvi_pixel_clock_s,
      serial_clock_i => dvi_serial_clock_s,
      tmds_i => tmds_s,
      pmod_o => pmod_dvi_o
      );

  dvi_encoder: nsl_dvi.encoder.dvi_10_encoder
    port map(
      reset_n_i => dvi_pixel_clock_reset_n_s,
      pixel_clock_i => dvi_pixel_clock_s,

      v_fp_m1_i => v_fp_m1_c,
      v_sync_m1_i => v_sync_m1_c,
      v_bp_m1_i => v_bp_m1_c,
      v_act_m1_i => v_act_m1_c,

      h_fp_m1_i => h_fp_m1_c,
      h_sync_m1_i => h_sync_m1_c,
      h_bp_m1_i => h_bp_m1_c,
      h_act_m1_i => h_act_m1_c,

      vsync_i => '0',
      hsync_i => '0',

      sof_o => sof_s,
      sol_o => sol_s,
      pixel_ready_o => pixel_ready_s,
      pixel_valid_i => pixel_valid_s,
      pixel_i => pixel_s,

      tmds_o => tmds_s
      );

  scope: block is
    constant font_c: font_t := nsl_indication.font_6x8.font_6x8_c;
    constant font_hscale_c: natural := 2;
    constant font_vscale_c: natural := 2;
    constant cell_width_c : natural := font_width(font_c) * font_hscale_c;
    constant cell_height_c : natural := font_height(font_c) * font_vscale_c;
    constant row_count_l2_c : natural := nsl_math.arith.log2(v_act_c / cell_height_c);
    constant column_count_l2_c : natural := nsl_math.arith.log2(h_act_c / cell_width_c);
    constant status_row_c : natural := v_act_c / cell_height_c - 1;

    constant color_count_l2_c : natural := 3;
    subtype color_t is unsigned(color_count_l2_c-1 downto 0);

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

    signal under_ready_s, under_valid_s : std_ulogic;
    signal over_ready_s, over_valid_s : std_ulogic;
    signal blend_ready_s, blend_valid_s : std_ulogic;
    signal under_color_s, over_color_s, blend_color_s : color_t;
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

        tick_i => sof_s,

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

    underlay: work.top.scope_renderer
      generic map(
        h_act_c => h_act_c,
        v_act_c => v_act_c,
        color_count_l2_c => color_count_l2_c,
        background_color_c => color_background_c,
        grid_color_c => color_grid_c,
        trace_color_c => color_trace_c,
        trace_amplitude_c => 300
        )
      port map(
        clock_i => dvi_pixel_clock_s,
        reset_n_i => dvi_pixel_clock_reset_n_s,

        sof_i => sof_s,
        sol_i => sol_s,
        color_ready_i => under_ready_s,
        color_valid_o => under_valid_s,
        color_o => under_color_s,

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
        font_vscale_c => font_vscale_c
        )
      port map(
        clock_i => dvi_pixel_clock_s,
        reset_n_i => dvi_pixel_clock_reset_n_s,

        sof_i => sof_s,
        sol_i => sol_s,
        color_ready_i => over_ready_s,
        color_valid_o => over_valid_s,
        color_o => over_color_s,

        text_i => text_s,
        color_i => colors_s
        );

    blender: nsl_dvi.blender.dvi_blender_color_key
      generic map(
        color_count_l2_c => color_count_l2_c,
        key_color_c => color_key_c
        )
      port map(
        overlay_ready_o => over_ready_s,
        overlay_valid_i => over_valid_s,
        overlay_color_i => over_color_s,

        underlay_ready_o => under_ready_s,
        underlay_valid_i => under_valid_s,
        underlay_color_i => under_color_s,

        color_ready_i => blend_ready_s,
        color_valid_o => blend_valid_s,
        color_o => blend_color_s
        );

    lookup: nsl_dvi.colormap.dvi_colormap_lookup
      generic map(
        color_count_l2_c => color_count_l2_c
        )
      port map(
        clock_i => dvi_pixel_clock_s,
        reset_n_i => dvi_pixel_clock_reset_n_s,

        palette_i => palette_c,

        sof_i => sof_s,
        sol_i => sol_s,
        pixel_ready_i => pixel_ready_s,
        pixel_valid_o => pixel_valid_s,
        pixel_o => pixel_s,

        color_ready_o => blend_ready_s,
        color_valid_i => blend_valid_s,
        color_i => blend_color_s
        );

  end block;

end architecture;
