library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library signalling;
use signalling.diff.all;

package pad is

  component diff_input_pad
    generic(
      diff_term : boolean := true;
      is_clock : boolean := false;
      invert : boolean := false
      );
    port(
      p_diff : in diff_pair;
      p_se : out std_ulogic
      );
  end component;

  component diff_output_pad
    generic(
      is_clock : boolean := false
      );
    port(
      p_se : in std_ulogic;
      p_diff : out diff_pair
      );
  end component;

end package pad;
