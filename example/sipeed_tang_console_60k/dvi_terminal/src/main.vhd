library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library work, nsl_color, nsl_io, nsl_clocking, nsl_data, nsl_dvi, nsl_math, nsl_signal_generator, nsl_event, nsl_sipeed, nsl_indication;
use nsl_color.rgb.all;
use nsl_math.fixed.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_indication.font.all;

entity main is
  generic (
    clock_i_hz_c : natural;
    -- Video mode, and the two clocks it calls for.  Both are exact:
    -- the solver refuses a rate it cannot hold.
    mode_c : nsl_dvi.mode.mode_t
    );
  port (
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    led_o: out std_ulogic_vector(0 to 1);

    dvi_clock_o : out nsl_io.diff.diff_pair;
    dvi_data_o : out nsl_io.diff.diff_pair_vector(0 to 2);

    uart_i : in std_ulogic
    );
end entity;

architecture beh of main is

  use nsl_dvi.mode.all;
  use nsl_clocking.pll.all;

  -- 720p50 needs 74.25MHz, which no single ratio reaches from 50MHz:
  -- the phase detector floor leaves the input divider at 1 or 2, and
  -- neither 50MHz nor 25MHz times a whole number lands on a multiple
  -- of 74.25MHz inside the VCO window.  Two stages do reach it: the
  -- first gets to 562.5MHz, from where the second can divide by 25
  -- and still stay above the floor.  This intermediate rate is
  -- chosen for this mode; another mode may want another one, or none
  -- at all.
  constant intermediate_hz_c : natural := 562_500_000;

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
  
  -- Interconnection
  signal blinker_s: unsigned(26 downto 0);

  signal dvi_ref_clock_s, dvi_pixel_clock_reset_n_s : std_ulogic;
  signal dvi_pixel_clock_s, dvi_serial_clock_s : std_ulogic;
  signal pll_locked_s : std_ulogic;

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

  ref_pll: nsl_clocking.pll.pll_multi
    generic map(
      config_c => ref_config_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      clock_o(0) => dvi_ref_clock_s,
      locked_o => pll_locked_s
      );

  video_pll: nsl_clocking.pll.pll_multi
    generic map(
      config_c => video_config_c
      )
    port map(
      clock_i => dvi_ref_clock_s,
      reset_n_i => pll_locked_s,
      clock_o => video_clock_s,
      locked_o => dvi_pixel_clock_reset_n_s
      );

  dvi_serial_clock_s <= video_clock_s(0);
  dvi_pixel_clock_s <= video_clock_s(1);

  driver: nsl_dvi.transceiver.dvi_driver
    generic map(
      driver_mode_c => "tlvds"
      )
    port map(
      reset_n_i => dvi_pixel_clock_reset_n_s,
      pixel_clock_i => dvi_pixel_clock_s,
      serial_clock_i => dvi_serial_clock_s,
      tmds_i => tmds_s,
      clock_o => dvi_clock_o,
      data_o => dvi_data_o
      );
  
   dvi_encoder: nsl_dvi.encoder.dvi_10_encoder
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
  
       sof_o => sof_s,
       sol_o => sol_s,
       pixel_ready_o => pixel_ready_s,
       pixel_valid_i => pixel_valid_s,
       pixel_i => pixel_s,
  
       tmds_o => tmds_s
       );

  term: block is
    constant font_c: font_t := nsl_indication.font_6x8.font_6x8_c;
--    constant font_c: font_t := nsl_indication.font_4x6.font_4x6_c;
    constant font_hscale_c: natural := 4;
    constant font_vscale_c: natural := 4;

    constant row_count_c: integer := mode_c.v.active / font_height(font_c) / font_vscale_c;
    constant row_count_l2_c:natural := nsl_math.arith.log2(row_count_c);
    constant column_count_c: integer := mode_c.h.active / font_width(font_c) / font_hscale_c;
    constant column_count_l2_c: natural := nsl_math.arith.log2(column_count_c);
    constant character_count_l2_c: natural := 8;

    subtype color_index_t is unsigned(1 downto 0);
    signal term_fg_s, term_bg_s: color_index_t;

    constant color_palette_c: nsl_color.rgb.rgb24_vector(0 to 2**color_index_t'length-1)
      := (nsl_color.rgb.rgb24_black,
          nsl_color.rgb.rgb24_red,
          nsl_color.rgb.rgb24_blue,
          nsl_color.rgb.rgb24_white);

    signal init_data_s: byte;
    signal init_valid_s: std_ulogic;

    type regs_t is
    record
      row: unsigned(row_count_l2_c-1 downto 0);
      column: unsigned(column_count_l2_c-1 downto 0);
      done: boolean;
    end record;

    signal r, rin: regs_t;
  begin    
    generator: nsl_dvi.terminal.terminal_text_buffer
      generic map(
        row_count_l2_c => row_count_l2_c,
        column_count_l2_c => column_count_l2_c,
        character_count_l2_c => character_count_l2_c,
        color_palette_c => color_palette_c,
        font_c => font_c,
        underline_support_c => false,
        font_hscale_c => font_hscale_c,
        font_vscale_c => font_vscale_c
        )
      port map(
        video_clock_i => dvi_pixel_clock_s,
        video_reset_n_i => dvi_pixel_clock_reset_n_s,

        sof_i => sof_s,
        sol_i => sol_s,
        pixel_ready_i => pixel_ready_s,
        pixel_valid_o => pixel_valid_s,
        pixel_o => pixel_s,

        term_clock_i => clock_i,
        term_reset_n_i => reset_n_i,

        row_i => r.row,
        column_i => r.column,
        enable_i => init_valid_s,
        write_i => init_valid_s,
        character_i => unsigned(init_data_s),
        foreground_i => term_fg_s,
        background_i => term_bg_s
        );

    term_fg_s <= "11";
    term_bg_s <= "00";

    regs: process (reset_n_i, clock_i)
    begin
      if rising_edge(clock_i) then
        r <= rin;
      end if;

      if reset_n_i = '0' then
        r.row <= (others => '0');
        r.column <= (others => '0');
        r.done <= false;
      end if;
    end process;

    transition: process(r, init_valid_s)
    begin
      rin <= r;

      if r.column /= column_count_c-1 then
        rin.column <= r.column + 1;
      elsif r.row /= row_count_c-1 then
        rin.row <= r.row + 1;
        rin.column <= (others => '0');
      else
        rin.done <= true;
      end if;
    end process;

    moore: process(r)
    begin
      if r.done then
        init_valid_s <= '0';
        init_data_s <= x"00";
      else
        init_valid_s <= '1';
        init_data_s <= byte(resize(r.row(3 downto 0) & r.column(3 downto 0), 8));
      end if;
    end process;
  end block;

end architecture;
