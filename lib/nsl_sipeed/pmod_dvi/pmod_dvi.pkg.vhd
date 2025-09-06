library ieee;
use ieee.std_logic_1164.all;

library nsl_digilent, nsl_dvi;

package pmod_dvi is
  
  component pmod_dvi_output is
    port(
      reset_n_i : in std_ulogic;
      pixel_clock_i : in std_ulogic;
      serial_clock_i : in std_ulogic;
      
      tmds_i : in nsl_dvi.dvi.symbol_vector_t;

      pmod_io : inout nsl_digilent.pmod.pmod_double_t
      );
  end component;

end package pmod_dvi;
