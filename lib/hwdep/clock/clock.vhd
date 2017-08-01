library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library hwdep;

package clock is

  component clock_output
    port(
      p_clk      : in  std_ulogic;
      p_clk_neg  : in  std_ulogic;
      p_port     : out std_ulogic
      );
  end component;

  component clock_internal
    port(
      p_clk      : out std_ulogic
      );
  end component;

end package clock;
