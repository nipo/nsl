library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.pmod_oled_rgb.all;

entity pmod_oled_rgb_io_driver is
  port(
    pmod_io: inout work.pmod.pmod_double_t;
    control_i : in oled_rgb_c
    );
end entity;

architecture beh of pmod_oled_rgb_io_driver is

begin

  pmod_io(1) <= control_i.spi.cs_n;
  pmod_io(2) <= control_i.spi.mosi;
  pmod_io(3) <= 'Z';
  pmod_io(4) <= control_i.spi.sck;
  pmod_io(5) <= control_i.dc;
  pmod_io(6) <= control_i.reset_n;
  pmod_io(7) <= control_i.vccen;
  pmod_io(8) <= control_i.en;

end architecture;
