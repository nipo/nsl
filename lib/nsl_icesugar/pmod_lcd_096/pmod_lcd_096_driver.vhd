library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work, nsl_sitronix, nsl_color, nsl_digilent, nsl_data, nsl_video;
use work.pmod_lcd_096.all;
use nsl_data.bytestream.all;

entity pmod_lcd_096_driver is
  generic(
    clock_i_hz_c : natural;
    config_c : nsl_video.pixel_stream.config_t;
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

    pixel_i : in nsl_video.pixel_stream.master_t;
    pixel_o : out nsl_video.pixel_stream.slave_t;

    synced_o : out std_ulogic;

    pmod_io : inout nsl_digilent.pmod.pmod_double_t
    );
end entity;

architecture beh of pmod_lcd_096_driver is

  signal control_s : lcd_096_c;

begin

  driver: nsl_sitronix.st7735.st7735_spi_driver
    generic map(
      clock_i_hz_c => clock_i_hz_c,
      config_c => config_c,
      spi_hz_c => spi_hz_c,
      geometry_c => nsl_video.mode.geometry(160, 80),
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

      pixel_i => pixel_i,
      pixel_o => pixel_o,
      synced_o => synced_o
      );

  io_driver: work.pmod_lcd_096.pmod_lcd_096_io_driver
    port map(
      pmod_io => pmod_io,
      control_i => control_s
      );

end architecture;
