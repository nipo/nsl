library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math;
use nsl_math.fixed.all;

package dither is

  component dither_ufixed is
    port(
      clock_i: in std_ulogic;
      reset_n_i : in std_ulogic;

      in_valid_i : in std_ulogic;
      in_i : in ufixed;
      out_ready_i : in std_ulogic;
      out_o : out ufixed
      );
  end component;

end package;
