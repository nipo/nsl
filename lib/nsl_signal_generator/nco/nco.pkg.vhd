library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math;
use nsl_math.fixed.all;

package nco is

  component nco_sinus is
    generic (
      scale_c : real := 1.0;
      trim_bits_c : natural := 0
      );
    port (
      clock_i: in std_ulogic;
      reset_n_i : in std_ulogic;
      -- In turns, i.e. (1/(2*pi)) radians
      angle_increment_i : in ufixed;
      value_o : out sfixed
      );
  end component;    
  
end package nco;
