library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math;
use nsl_math.fixed.all;

-- Clock generators
package generator is

  -- Fractional tick generator. Asserts tick_o for exactly one cycle every
  -- period_i cycles on average (period is a fixed point value here).
  component tick_generator is
    port(
      clock_i    : in  std_ulogic;
      reset_n_i  : in  std_ulogic;

      period_i : in ufixed;
      
      tick_o   : out std_ulogic
      );
  end component;

  -- Fractional clock generator. Resulting signal is not buffered. This is
  -- mostly suitable for generating outputs.
  component clock_divisor is
    port(
      clock_i    : in  std_ulogic;
      reset_n_i  : in  std_ulogic;

      period_i : in ufixed;
      
      clock_o   : out std_ulogic
      );
  end component;

end package generator;
