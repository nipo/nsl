library ieee;
use ieee.std_logic_1164.all;

package topcell is
  component top is
    port (
      swclk: in std_ulogic;
      swdio: inout std_logic
      );
  end component;
end package topcell;
