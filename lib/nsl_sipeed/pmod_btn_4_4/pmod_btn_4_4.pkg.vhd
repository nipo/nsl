library ieee;
use ieee.std_logic_1164.all;

library nsl_digilent;

package pmod_btn_4_4 is
  
  component pmod_btn_4_4_input is
    port(
      pmod_io : inout nsl_digilent.pmod.pmod_double_t;

      s_o : out std_ulogic_vector(1 to 4);
      k_o : out std_ulogic_vector(1 to 4)
      );
  end component;

end package pmod_btn_4_4;
