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
    generic(
      -- Scale of result polar coordinates
      scale_c : real := 1.0
      );
    port (
      clock_i: in std_ulogic;
      reset_n_i : in std_ulogic;

      -- angle in radians / 2π, in [0 .. 1)
      -- angle_i range left should be -1.
      angle_i : in ufixed;
      ready_o : out std_ulogic;
      valid_i : in std_ulogic;

      -- Sin/Cos in [-scale .. +scale). y and x may have different
      -- dynamic ranges.  They should be able to hold dynamic range of
      -- scaled output, if not, staturated value is used.
      y_o : out sfixed;
      x_o : out sfixed;
      valid_o : out std_ulogic;
      ready_i : in std_ulogic
      );
  end component;    

  -- Rectangular extraction for polar angle (assimung r = 1).
  -- This implementation is an iterative cordic.
  component rect_cordic is
    generic(
      scale_c : real := 1.0
      );
    port (
      clock_i: in std_ulogic;
      reset_n_i : in std_ulogic;

      -- angle in radians / 2π, in [0 .. 1)
      -- angle_i range left should be -1.
      angle_i : in ufixed;
      ready_o : out std_ulogic;
      valid_i : in std_ulogic;

      -- Sin/Cos in [-scale .. +scale). y and x may have different
      -- dynamic ranges.  They should be able to hold dynamic range of
      -- scaled output, if not, staturated value is used.
      x_o : out sfixed;
      y_o : out sfixed;
      valid_o : out std_ulogic;
      ready_i : in std_ulogic
      );
  end component;    

end package trigonometry;
