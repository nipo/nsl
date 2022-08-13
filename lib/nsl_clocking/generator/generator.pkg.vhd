library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math;
use nsl_math.fixed.all;

-- Clock generators
package generator is

  -- Fractional clock generator. Resulting signal is not
  -- buffered. This is mostly suitable for generating outputs.
  --
  -- Beware of jitter of generated clock. It has a max jitter of
  -- clock_i period.
  component clock_generator is
    port(
      clock_i    : in  std_ulogic;
      reset_n_i  : in  std_ulogic;

      period_i : in ufixed;
      
      clock_o   : out std_ulogic
      );
  end component;

end package generator;
