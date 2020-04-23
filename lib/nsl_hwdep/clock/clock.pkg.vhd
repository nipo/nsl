library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package clock is

  component clock_internal
    port(
      clock_o  : out std_ulogic
      );
  end component;

end package clock;
