library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_io;
use nsl_io.diff.all;

package pad is

  component pad_diff_clock_input
    generic(
      diff_term : boolean := true;
      invert    : boolean := false
      );
    port(
      p_pad : in  diff_pair;
      p_clk : out diff_pair
      );
  end component;

  component pad_diff_input
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

  component pad_diff_output
    generic(
      is_clock : boolean := false
      );
    port(
      p_se : in std_ulogic;
      p_diff : out diff_pair
      );
  end component;

  component pad_tmds_output
    generic(
      invert_c : boolean := false;
      driver_mode_c : string := "default"
      );
    port(
      data_i : in std_ulogic;
      pad_o : out diff_pair
      );
  end component;

  component pad_tmds_input
    generic(
      invert_c : boolean := false
      );
    port(
      data_o : out std_ulogic;
      pad_i : in diff_pair
      );
  end component;

end package pad;
