library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work, nsl_spi, nsl_color;

-- Digilent Pmod OLEDrgb, a SSD1331-driven 96x64 RGB OLED module on a
-- double Pmod connector.
package pmod_oled_rgb is

  type oled_rgb_c is
  record
    spi: nsl_spi.spi.spi_slave_i;
    dc, reset_n, vccen, en: std_ulogic;
  end record;

  component pmod_oled_rgb_io_driver is
    port(
      pmod_io: inout work.pmod.pmod_double_t;
      control_i : in oled_rgb_c
      );
  end component;

  -- Complete module driver, wraps
  -- nsl_solomonsystech.ssd1331.ssd1331_spi_driver and maps it to the
  -- module pinout.  See the SSD1331 driver for interface semantics.
  component pmod_oled_rgb_driver is
    generic(
      clock_i_hz_c : natural;
      spi_hz_c : natural := 6_666_666
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

      pmod_io : inout work.pmod.pmod_double_t
      );
  end component;

end package pmod_oled_rgb;
