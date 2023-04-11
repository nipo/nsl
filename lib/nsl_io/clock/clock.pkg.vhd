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

  component clock_output_se_to_diff is
    port(
      clock_i  : in std_ulogic;
      pin_o : out nsl_io.diff.diff_pair
      );
  end component;

  component clock_output_se_divided is
    generic(
      divisor_c: positive := 1
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;
      port_o: out std_ulogic
      );
  end component;

end package clock;
