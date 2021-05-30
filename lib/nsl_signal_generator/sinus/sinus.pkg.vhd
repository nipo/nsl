library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math;
use nsl_math.fixed.all;

package sinus is

  -- Table-based sinus calculation
  -- Delay from input to output is unspecidied but constant.
  component sinus_stream_table is
    generic (
      -- Scale to apply to result before outputting it
      scale_c : real := 1.0
      );
    port (
      clock_i: in std_ulogic;
      reset_n_i : in std_ulogic;

      -- angle in radians / (2*π), in [0 .. 1)
      -- angle_i'left must be -1.
      angle_i : in ufixed;

      -- Sin in [-1 .. +1], multiplied by scale.  It is up to
      -- instantiation to ensure value_o can fit [-scale_c : scale_c]
      -- range. Value is saturated to sfixed range if it does not fit.
      value_o : out sfixed
      );
  end component;    

  -- Pipelined sinus calculation.
  -- Delay from input to output is unspecidied but constant.
  component sinus_stream_cordic is
    generic (
      -- Scale to apply to result before outputting it
      scale_c : real := 1.0
      );
    port (
      clock_i: in std_ulogic;
      reset_n_i : in std_ulogic;

      -- angle in radians / (2*π), in [0 .. 1)
      -- angle_i'left must be -1.
      angle_i : in ufixed;

      -- Sin in [-1 .. +1], multiplied by scale.  It is up to
      -- instantiation to ensure value_o can fit [-scale_c : scale_c]
      -- range. Value is saturated to sfixed range if it does not fit.
      value_o : out sfixed
      );
  end component;    

  component sinus_stream_table_interpolated is
    generic (
      lookup_bits_c : integer := 9;
      table_bits_c : integer := 9;
      scale_c : real := 1.0
      );
    port (
      clock_i: in std_ulogic;
      reset_n_i : in std_ulogic;

      angle_i : in ufixed;
      value_o : out sfixed
      );
  end component;

  component sinus_stream is
    generic (
      scale_c : real := 1.0;
      -- "table". See above
      implementation_c : string := "table"
      );
    port (
      clock_i: in std_ulogic;
      reset_n_i : in std_ulogic;

      angle_i : in ufixed;
      value_o : out sfixed
      );
  end component;    

end package sinus;
