library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_io;

package clock is

  component clock_output_diff_to_se is
    port(
      clock_i : in nsl_io.diff.diff_pair;
      port_o: out std_ulogic
      );
  end component;

  component clock_output_se_to_se is
    port(
      clock_i : in std_ulogic;
      port_o: out std_ulogic
      );
  end component;

end package clock;
