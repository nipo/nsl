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

  -- Pipelined sinus calculation.
  -- Delay from input to output is unspecidied but constant.
  component sinus_stream is
    generic (
      -- Scale to apply to result before outputting it
      scale_c : real := 1.0
      );
    port (
      clock_i: in std_ulogic;
      reset_n_i : in std_ulogic;

      -- angle in radians / π, in [0 .. 2)
      -- angle_i'left must be 0.
      angle_i : in ufixed;

      -- Cos in [-1 .. +1], multiplied by scale.  It is up to
      -- instantiation to ensure value_o can fit [-scale_c : scale_c]
      -- range. Value is saturated to sfixed range if not.
      value_o : out sfixed
      );
  end component;    

end package trigonometry;
