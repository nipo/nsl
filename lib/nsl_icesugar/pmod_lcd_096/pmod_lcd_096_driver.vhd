library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work, nsl_sitronix, nsl_color, nsl_digilent, nsl_data;
use work.pmod_lcd_096.all;
use nsl_data.bytestream.all;

entity pmod_lcd_096_driver is
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
end entity;

architecture beh of pmod_lcd_096_driver is

  signal control_s : lcd_096_c;

begin

  driver: nsl_sitronix.st7735.st7735_spi_driver
    generic map(
      clock_i_hz_c => clock_i_hz_c,
      spi_hz_c => spi_hz_c,
      width_c => 160,
      height_c => 80,
      column_offset_c => column_offset_c,
      row_offset_c => row_offset_c,
      madctl_c => madctl_c,
      invert_c => invert_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      enable_i => enable_i,
      refresh_i => refresh_i,

      spi_o => control_s.spi,
      dc_o => control_s.dc,
      reset_n_o => control_s.reset_n,

      sof_o => sof_o,
      sol_o => sol_o,
      pixel_ready_o => pixel_ready_o,
      pixel_valid_i => pixel_valid_i,
      pixel_i => pixel_i
      );

  io_driver: work.pmod_lcd_096.pmod_lcd_096_io_driver
    port map(
      pmod_io => pmod_io,
      control_i => control_s
      );

end architecture;
