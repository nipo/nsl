library ieee;
use ieee.std_logic_1164.all;

library nsl_digilent;

entity pmod_8xled_driver is
  port(
    pmod_io : inout nsl_digilent.pmod.pmod_double_t;

    led_i : in std_ulogic_vector(1 to 8)
    );
end entity;

architecture beh of pmod_8xled_driver is

begin

  pmod_io(1) <= not led_i(2);
  pmod_io(2) <= not led_i(4);
  pmod_io(3) <= not led_i(6);
  pmod_io(4) <= not led_i(8);
  pmod_io(5) <= not led_i(1);
  pmod_io(6) <= not led_i(3);
  pmod_io(7) <= not led_i(5);
  pmod_io(8) <= not led_i(7);
  
end architecture;
  
