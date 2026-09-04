library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work, nsl_digilent;
use work.pmod_lcd_096.all;

entity pmod_lcd_096_io_driver is
  port(
    pmod_io: inout nsl_digilent.pmod.pmod_double_t;
    control_i : in lcd_096_c
    );
end entity;

architecture beh of pmod_lcd_096_io_driver is

begin

  -- SPI Pmod type-2 style layout, D/C in place of MISO
  pmod_io(1) <= control_i.spi.cs_n;
  pmod_io(2) <= control_i.spi.mosi;
  pmod_io(3) <= control_i.dc;
  pmod_io(4) <= control_i.spi.sck;
  pmod_io(5) <= 'Z';
  pmod_io(6) <= 'Z';
  pmod_io(7) <= 'Z';
  pmod_io(8) <= control_i.reset_n;

end architecture;
