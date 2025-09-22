library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library work, nsl_color, nsl_io, nsl_clocking, nsl_data, nsl_dvi, nsl_math, nsl_signal_generator, nsl_event, nsl_digilent, nsl_sipeed, nsl_indication, nsl_uart;
use nsl_color.rgb.all;
use nsl_digilent.pmod.all;
use nsl_math.fixed.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_indication.font.all;

entity main is
  generic (
    clock_i_hz_c : natural
    );
  port (
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    switch_i : in std_ulogic_vector(0 to 3);
    led_o: out std_ulogic_vector(0 to 1);

    pmod_dvi_o : out pmod_double_t;

    uart_i : in std_ulogic
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
  constant dvi_fps_c : real := 50.0;

  -- Generate arbitrary pixel/serial clock by cascading MMCM and PLL.
  -- MMCM generates a pixel clock with any ratio (using fractional divisor)
  -- PLL does pixel clock x5 to get to serial clock.
  constant mmcm_vco_freq_c : real := 1.125e9 / 2.0;
  constant mmcm_ckin_div_c : integer := 2;
  -- Pixel clock, derived from timings above
  constant dvi_pixel_clock_freq_c : real := real((v_fp_c + v_sync_c + v_bp_c + v_act_c)
                                                  * (h_fp_c + h_sync_c + h_bp_c + h_act_c))
                                                  * dvi_fps_c;
  constant dvi_serial_clock_freq_c : real := dvi_pixel_clock_freq_c * 5.0;
  constant dvi_pll_vco_mult_c : integer := integer(1600.0e6 / dvi_serial_clock_freq_c);
  constant dvi_pll_vco_freq_c : real := real(dvi_pll_vco_mult_c) * dvi_serial_clock_freq_c;
  constant dvi_pll_ckin_div_c : integer := 1;

  -- Translation to constants needed by components
  constant v_fp_m1_c   : unsigned(3-1 downto 0)  := to_unsigned(v_fp_c-1, 3);
  constant v_sync_m1_c : unsigned(3-1 downto 0)  := to_unsigned(v_sync_c-1, 3);
  constant v_bp_m1_c   : unsigned(5-1 downto 0)  := to_unsigned(v_bp_c-1, 5);
  constant v_act_m1_c  : unsigned(10-1 downto 0) := to_unsigned(v_act_c-1, 10);
  constant h_fp_m1_c   : unsigned(9-1 downto 0)  := to_unsigned(h_fp_c-1, 9);
  constant h_sync_m1_c : unsigned(6-1 downto 0)  := to_unsigned(h_sync_c-1, 6);
  constant h_bp_m1_c   : unsigned(8-1 downto 0)  := to_unsigned(h_bp_c-1, 8);
  constant h_act_m1_c  : unsigned(11-1 downto 0) := to_unsigned(h_act_c-1, 11);
  
  -- Interconnection
  signal blinker_s: unsigned(26 downto 0);

  signal dvi_ref_clock_s, dvi_pll_reset, dvi_pll_feedback, dvi_pixel_clock_reset_n_s : std_ulogic;
  signal dvi_pixel_clock_s, dvi_serial_clock_s : std_ulogic;
  signal dvi_pixel_clock_unb_s, dvi_serial_clock_unb_s : std_ulogic;
  signal pll_locked_s, pll_feedback_s, pll_reset_s: std_ulogic;

  signal tmds_s : nsl_dvi.dvi.symbol_vector_t;

  signal sol_s, sof_s, pixel_ready_s : std_ulogic;
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
  
       sof_o => sof_s,
       sol_o => sol_s,
       pixel_ready_o => pixel_ready_s,
       pixel_i => pixel_s,
  
       tmds_o => tmds_s
       );

  term: block is
    constant font_c: font_t := nsl_indication.font_6x8.font_6x8_c;
    constant font_hscale_c: natural := 4;
    constant font_vscale_c: natural := 4;

    constant row_count_c: integer := v_act_c / font_height(font_c) / font_vscale_c;
    constant row_count_l2_c:natural := nsl_math.arith.log2(row_count_c);
    constant column_count_c: integer := h_act_c / font_width(font_c) / font_hscale_c;
    constant column_count_l2_c: natural := nsl_math.arith.log2(column_count_c);
    constant character_count_l2_c: natural := 8;

    subtype color_index_t is unsigned(1 downto 0);
    signal term_fg_s, term_bg_s: color_index_t;

    constant color_palette_c: nsl_color.rgb.rgb24_vector(0 to 2**color_index_t'length-1)
      := (nsl_color.rgb.rgb24_black,
          nsl_color.rgb.rgb24_red,
          nsl_color.rgb.rgb24_blue,
          nsl_color.rgb.rgb24_white);

    constant uart_divisor_c: unsigned
      := nsl_math.arith.to_unsigned_auto(clock_i_hz_c / 115200 - 1);

    signal uart_data_s: byte;
    signal uart_valid_s: std_ulogic;

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
        pixel_o => pixel_s,

        term_clock_i => clock_i,
        term_reset_n_i => reset_n_i,

        row_i => r.row,
        column_i => r.column,
        enable_i => uart_valid_s,
        write_i => uart_valid_s,
        character_i => unsigned(uart_data_s),
        foreground_i => term_fg_s,
        background_i => term_bg_s
        );

    term_fg_s <= unsigned(switch_i(0 to 1));
    term_bg_s <= unsigned(switch_i(2 to 3));

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

    transition: process(r, uart_valid_s)
    begin
      rin <= r;

      if r.column /= column_count_c-1 then
        rin.column <= r.column + 1;
      elsif r.row /= row_count_c-1 then
        rin.row <= r.row + 1;
        rin.column <= (others => '0');
      else
--        rin.row <= (others => '0');
--        rin.column <= (others => '0');
        rin.done <= true;
      end if;
    end process;

    moore: process(r)
    begin
      if r.done then
        uart_valid_s <= '0';
        uart_data_s <= x"00";
      else
        uart_valid_s <= '1';
        uart_data_s <= byte(resize(r.row(3 downto 0) & r.column(3 downto 0), 8));
      end if;
    end process;
--    uart_rx: nsl_uart.serdes.uart_rx
--      generic map(
--        bit_count_c => 8,
--        stop_count_c => 1,
--        parity_c => nsl_uart.serdes.PARITY_NONE,
--        rts_active_c => '0'
--        )
--      port map(
--        clock_i => clock_i,
--        reset_n_i => reset_n_i,
--        divisor_i => uart_divisor_c,
--        uart_i => uart_i,
--
--        data_o => uart_data_s,
--        valid_o => uart_valid_s);
  end block;

end architecture;
