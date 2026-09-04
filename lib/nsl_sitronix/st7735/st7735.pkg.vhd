library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_spi, nsl_data, nsl_color;
use nsl_data.bytestream.all;

-- ST7735S is a 132RGB x 162 TFT LCD controller.  It is typically
-- attached to smaller glass; the visible window then sits at an
-- offset inside the graphic RAM that depends on the panel.
--
-- Unlike Solomon Systech controllers, command parameters are data
-- bytes (D/C high), only the command opcode itself has D/C low.
package st7735 is

  constant gram_width_c : natural := 132;
  constant gram_height_c : natural := 162;

  -- [Command]
  constant cmd_nop     : byte := x"00";
  constant cmd_swreset : byte := x"01";
  constant cmd_slpin   : byte := x"10";
  constant cmd_slpout  : byte := x"11";
  constant cmd_ptlon   : byte := x"12";
  constant cmd_noron   : byte := x"13";
  constant cmd_invoff  : byte := x"20";
  constant cmd_invon   : byte := x"21";
  -- [Command] [curve]
  constant cmd_gamset  : byte := x"26";
  -- [Command]
  constant cmd_dispoff : byte := x"28";
  constant cmd_dispon  : byte := x"29";
  -- [Command] [start msb] [start lsb] [end msb] [end lsb] (inclusive)
  constant cmd_caset   : byte := x"2a";
  constant cmd_raset   : byte := x"2b";
  -- [Command] pixel data...
  constant cmd_ramwr   : byte := x"2c";
  constant cmd_ramrd   : byte := x"2e";
  -- [Command]
  constant cmd_teoff   : byte := x"34";
  -- [Command] [mode]
  constant cmd_teon    : byte := x"35";
  -- [Command] [flags]
  constant cmd_madctl  : byte := x"36";
  constant cmd_madctl_row_reverse     : byte := "1-------";
  constant cmd_madctl_column_reverse  : byte := "-1------";
  constant cmd_madctl_row_column_swap : byte := "--1-----";
  constant cmd_madctl_line_reverse    : byte := "---1----";
  constant cmd_madctl_bgr             : byte := "----1---";
  constant cmd_madctl_hrefresh_rev    : byte := "-----1--";
  -- [Command]
  constant cmd_idmoff  : byte := x"38";
  constant cmd_idmon   : byte := x"39";
  -- [Command] [format]
  constant cmd_colmod  : byte := x"3a";
  constant cmd_colmod_12bpp : byte := x"03";
  constant cmd_colmod_16bpp : byte := x"05";
  constant cmd_colmod_18bpp : byte := x"06";

  -- Refreshes the panel from a DVI-style pixel stream over the serial
  -- interface, see nsl_solomonsystech.ssd1331.ssd1331_spi_driver for
  -- the interface contract.
  --
  -- After enable_i is asserted, driver resets the controller, wakes
  -- it from sleep, configures it, streams a first frame, and only
  -- then turns the display on.  Deasserting enable_i turns the
  -- display off and puts the controller in sleep, then holds it in
  -- reset.
  --
  -- Default window and orientation generics suit the common 0.96"
  -- 160x80 IPS panels in landscape (row/column swap): visible window
  -- offset 1 on the long axis, 26 on the short one, inversion on.
  component st7735_spi_driver is
    generic(
      clock_i_hz_c : natural;
      spi_hz_c : natural := 15_000_000;

      width_c : natural := 160;
      height_c : natural := 80;
      column_offset_c : natural := 1;
      row_offset_c : natural := 26;
      madctl_c : byte := x"68";
      invert_c : boolean := true
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
