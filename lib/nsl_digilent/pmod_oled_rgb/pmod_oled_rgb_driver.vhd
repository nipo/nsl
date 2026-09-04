library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work, nsl_solomonsystech, nsl_color;
use work.pmod_oled_rgb.all;

entity pmod_oled_rgb_driver is
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
end entity;

architecture beh of pmod_oled_rgb_driver is

  signal control_s : oled_rgb_c;

begin

  driver: nsl_solomonsystech.ssd1331.ssd1331_spi_driver
    generic map(
      clock_i_hz_c => clock_i_hz_c,
      spi_hz_c => spi_hz_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      enable_i => enable_i,
      refresh_i => refresh_i,

      spi_o => control_s.spi,
      dc_o => control_s.dc,
      reset_n_o => control_s.reset_n,
      vcc_en_o => control_s.vccen,
      power_en_o => control_s.en,

      sof_o => sof_o,
      sol_o => sol_o,
      pixel_ready_o => pixel_ready_o,
      pixel_valid_i => pixel_valid_i,
      pixel_i => pixel_i
      );

  io_driver: work.pmod_oled_rgb.pmod_oled_rgb_io_driver
    port map(
      pmod_io => pmod_io,
      control_i => control_s
      );

end architecture;
