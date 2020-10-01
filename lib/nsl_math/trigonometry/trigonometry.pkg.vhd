library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math;
use nsl_math.fixed.all;

package trigonometry is

  -- Rectangular extraction for polar angle (assimung r = 1).
  -- This implementation is a precalculated table, but in/out handshake allows
  -- to implement it with a cordic core instead.
  component rect_table is
    port (
      clock_i: in std_ulogic;
      reset_n_i : in std_ulogic;

      -- angle in radians / π, in [0 .. 2)
      -- angle_i range left must be 0.
      angle_i : in ufixed;
      ready_o : out std_ulogic;
      valid_i : in std_ulogic;

      -- Sin/Cos in [-1 .. +1) (saturated just below +1)
      -- sinus_o/cosinus_o range left must be 0.
      -- sinus and cosinus may have different dynamic ranges.
      sinus_o : out sfixed;
      cosinus_o : out sfixed;
      valid_o : out std_ulogic;
      ready_i : in std_ulogic
      );
  end component;    
  
end package trigonometry;
