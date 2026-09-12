library ieee, nsl_dvi;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work, nsl_color, nsl_io, nsl_clocking, nsl_digilent;
use nsl_color.rgb.all;
use nsl_digilent.pmod.all;

package top is
    
  component main is
    generic (
      clock_i_hz_c : natural;
      mode_c : nsl_dvi.mode.mode_t
      );
    port (
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      switch_i : in std_ulogic_vector(0 to 3);
      led_o: out std_ulogic_vector(0 to 1);

      pmod_dvi_o : out pmod_double_t;

      uart_i: in std_ulogic
      );
  end component;



end package;
