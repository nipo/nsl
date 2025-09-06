library ieee;
use ieee.std_logic_1164.all;

library nsl_digilent;

package pmod_8xled is
  
  component pmod_8xled_driver is
    port(
      pmod_io : inout nsl_digilent.pmod.pmod_double_t;

      led_i : in std_ulogic_vector(1 to 8)
      );
  end component;

end package pmod_8xled;
