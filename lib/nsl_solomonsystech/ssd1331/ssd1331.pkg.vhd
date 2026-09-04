library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_spi, nsl_data, nsl_color;
use nsl_data.bytestream.all;

-- SSD1331 is a 96x64 RGB OLED panel controller.
package ssd1331 is

  constant max_width_c: natural := 96;
  constant max_height_c: natural := 64;

  -- [Command] [start col] [end col] (inclusive)
  constant cmd_column_setup : byte := x"15";
  -- [Command] [start row] [end row] (inclusive)
  constant cmd_row_setup : byte := x"75";
  -- [Command] [contrast]
  constant cmd_a_segment_contrast : byte := x"81";
  constant cmd_b_segment_contrast : byte := x"82";
  constant cmd_c_segment_contrast : byte := x"83";
  -- [Command] [value]
  constant cmd_current_attenuation : byte := x"87";
  -- [Command] [value]
  constant cmd_a_precharge_speed : byte := x"8a";
  constant cmd_b_precharge_speed : byte := x"8b";
  constant cmd_c_precharge_speed : byte := x"8c";
  -- [Command] [flags]
  constant cmd_driver_remap : byte := x"a0";
  constant cmd_driver_remap_address_inc_vertical : byte := "-------1";
  constant cmd_driver_remap_column_reverse       : byte := "------1-";
  constant cmd_driver_remap_bgr                  : byte := "-----1--";
  constant cmd_driver_remap_com_swap             : byte := "----1---";
  constant cmd_driver_remap_com_reverse          : byte := "---1----";
  constant cmd_driver_remap_com_split            : byte := "--1-----";
  constant cmd_driver_remap_color_256            : byte := "00------";
  constant cmd_driver_remap_color_64k            : byte := "01------";
  constant cmd_driver_remap_color_64k2           : byte := "10------";
  -- [Command] [value]
  constant cmd_display_start_line : byte := x"a1";
  -- [Command] [value]
  constant cmd_vertical_offset : byte := x"a2";
  -- [Command]
  constant cmd_display_normal  : byte := x"a4";
  constant cmd_display_all_on  : byte := x"a5";
  constant cmd_display_all_off : byte := x"a6";
  constant cmd_display_reverse : byte := x"a7";
  -- [Command] [value]
  constant cmd_multiplex_ratio : byte := x"a8";
  -- [Command] [0x00] [contrast A] [contrast B] [contrast C] [precharge voltage]
  constant cmd_dim_mode_setup : byte := x"ab";
  -- [Command] [0x8e] (mandatory, selects external Vcc supply)
  constant cmd_master_config : byte := x"ad";
  constant cmd_master_config_value : byte := x"8e";
  -- [Command]
  constant cmd_display_on_dim    : byte := x"ac";
  constant cmd_display_sleep     : byte := x"ae";
  constant cmd_display_on_normal : byte := x"af";
  -- [Command] [xx] xx=1a: power save, xx=0b: run
  constant cmd_power_save : byte := x"b0";
  constant cmd_power_save_on  : byte := x"1a";
  constant cmd_power_save_off : byte := x"0b";
  -- [Command] [ba] phase 1 (a) and phase 2 (b) period, 0 excluded
  constant cmd_phase_period : byte := x"b1";
  -- [Command] [da] clock divider (a, ratio minus one) and oscillator frequency (d)
  constant cmd_clock_divider : byte := x"b3";
  -- [Command] 32*[ww] pulse width for gray scale table
  constant cmd_gray_scale : byte := x"b8";
  -- [Command] Set linear gray scale
  constant cmd_gray_scale_linear : byte := x"b9";
  -- [Command] [value] 0 = 0.1*vcc, 0x3e = 0.5*vcc
  constant cmd_pre_charge_level : byte := x"bb";
  -- [Command] [value]
  constant cmd_com_deselect_voltage : byte := x"be";
  constant cmd_com_deselect_voltage_p44_vcc : byte := x"00";
  constant cmd_com_deselect_voltage_p52_vcc : byte := x"10";
  constant cmd_com_deselect_voltage_p61_vcc : byte := x"20";
  constant cmd_com_deselect_voltage_p71_vcc : byte := x"30";
  constant cmd_com_deselect_voltage_p83_vcc : byte := x"3e";
  -- [Command] [value]
  constant cmd_lock : byte := x"fd";
  constant cmd_lock_lock : byte := x"16";
  constant cmd_lock_open : byte := x"12";
  -- [Command] [x1] [y1] [x2] [y2] [cc] [bb] [aa]
  constant cmd_line_draw : byte := x"21";
  -- [Command] [x1] [y1] [x2] [y2] [line cc] [line bb] [line aa] [fill cc] [fill bb] [fill aa]
  constant cmd_rect_draw : byte := x"22";
  -- [Command] [x1] [y1] [x2] [y2] [new x] [new y]
  constant cmd_copy : byte := x"23";
  -- [Command] [x1] [y1] [x2] [y2]
  constant cmd_dim_window : byte := x"24";
  -- [Command] [x1] [y1] [x2] [y2]
  constant cmd_clear_window : byte := x"25";
  -- [Command] [flags]
  constant cmd_fill_mode : byte := x"26";
  constant cmd_fill_mode_rect_fill : byte := "-------1";
  constant cmd_fill_mode_copy_wrap : byte := "------1-";

  -- Initialization command stream, 65k color mode, full panel, external
  -- Vcc.  Display-on is not part of it: it should only be sent once
  -- GDDRAM has defined contents, or the panel flashes random pixels.
  constant init_sequence_c : byte_string := from_hex(
    "fd12"      -- unlock
    & "ae"      -- sleep
    & "a072"    -- remap: 65k color, COM split, COM reverse scan
    & "a100"    -- start line 0
    & "a200"    -- vertical offset 0
    & "a4"      -- normal display
    & "a83f"    -- 64-line multiplex
    & "ad8e"    -- master config, external Vcc
    & "b00b"    -- power save off
    & "b131"    -- phase periods
    & "b3f0"    -- clock divider / oscillator frequency
    & "8a64"    -- precharge speeds
    & "8b78"
    & "8c64"
    & "bb3a"    -- precharge voltage
    & "be3e"    -- COM deselect voltage
    & "8706"    -- current attenuation
    & "8191"    -- contrasts
    & "8250"
    & "837d");

  -- Refreshes the panel from a DVI-style pixel stream over the serial
  -- interface.
  --
  -- After enable_i is asserted, driver powers the module up (power
  -- switches, reset, init sequence), streams a first frame, and only
  -- then turns the display on.  It then refreshes the whole panel
  -- whenever refresh_i is asserted while idle.  Deasserting enable_i
  -- powers the module down in order; init and first frame run again on
  -- next assertion.
  --
  -- Frame generator interface follows nsl_dvi.encoder.dvi_10_encoder:
  -- sof_o strobes once per frame before the first sol_o, sol_o strobes
  -- before the first pixel of each line, pixel_ready_o is asserted
  -- every cycle a pixel is taken.  Deasserting pixel_valid_i stalls
  -- the serial interface mid-frame.
  component ssd1331_spi_driver is
    generic(
      clock_i_hz_c : natural;
      spi_hz_c : natural := 6_666_666
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      enable_i : in std_ulogic := '1';
      refresh_i : in std_ulogic := '1';

      -- Connection to display controller
      spi_o : out nsl_spi.spi.spi_slave_i;
      dc_o : out std_ulogic;
      reset_n_o : out std_ulogic;
      -- Panel supply switch, asserted after reset cycle
      vcc_en_o : out std_ulogic;
      -- Logic supply switch, asserted first on power-up, last on
      -- power-down.  May be left unconnected when logic supply is not
      -- switchable
      power_en_o : out std_ulogic;

      -- Connection to frame generator
      sof_o : out std_ulogic;
      sol_o : out std_ulogic;
      pixel_ready_o : out std_ulogic;
      pixel_valid_i : in std_ulogic := '1';
      -- Encoded to RGB565 by truncation
      pixel_i : in nsl_color.rgb.rgb24
      );
  end component;

end package;
