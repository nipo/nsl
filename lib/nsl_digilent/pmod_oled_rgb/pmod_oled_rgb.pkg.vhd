library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work, nsl_spi, nsl_color, nsl_video;

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
      config_c : nsl_video.pixel_stream.config_t;
      spi_hz_c : natural := 6_666_666
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      enable_i : in std_ulogic := '1';
      refresh_i : in std_ulogic := '1';

      pixel_i : in nsl_video.pixel_stream.master_t;
      pixel_o : out nsl_video.pixel_stream.slave_t;

      synced_o : out std_ulogic;

      pmod_io : inout work.pmod.pmod_double_t
      );
  end component;

end package pmod_oled_rgb;
