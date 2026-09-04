library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work, nsl_spi, nsl_color, nsl_digilent, nsl_data;
use nsl_data.bytestream.all;

-- MuseLab iCESugar 0.96" LCD Pmod, a ST7735S-driven 160x80 IPS panel
-- on a double Pmod connector.
package pmod_lcd_096 is

  type lcd_096_c is
  record
    spi: nsl_spi.spi.spi_slave_i;
    dc, reset_n: std_ulogic;
  end record;

  component pmod_lcd_096_io_driver is
    port(
      pmod_io: inout nsl_digilent.pmod.pmod_double_t;
      control_i : in lcd_096_c
      );
  end component;

  -- Complete module driver, wraps
  -- nsl_sitronix.st7735.st7735_spi_driver and maps it to the module
  -- pinout.  See the ST7735 driver for interface semantics.
  -- Orientation and window generics are passed through for panel
  -- bring-up adjustments.
  component pmod_lcd_096_driver is
    generic(
      clock_i_hz_c : natural;
      spi_hz_c : natural := 15_000_000;
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

      sof_o : out std_ulogic;
      sol_o : out std_ulogic;
      pixel_ready_o : out std_ulogic;
      pixel_valid_i : in std_ulogic := '1';
      pixel_i : in nsl_color.rgb.rgb24;

      pmod_io : inout nsl_digilent.pmod.pmod_double_t
      );
  end component;

end package pmod_lcd_096;
