library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math;
use nsl_math.fixed.all;

package generator is

  component tick_generator is
    port(
      clock_i    : in  std_ulogic;
      reset_n_i  : in  std_ulogic;

      period_i : in ufixed;
      
      tick_o   : out std_ulogic
      );
  end component;

  component clock_divisor is
    port(
      clock_i    : in  std_ulogic;
      reset_n_i  : in  std_ulogic;

      period_i : in ufixed;
      
      clock_o   : out std_ulogic
      );
  end component;

end package generator;
