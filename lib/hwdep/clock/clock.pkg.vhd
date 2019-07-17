library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library hwdep;

package clock is

  component clock_internal
    port(
      p_clk      : out std_ulogic
      );
  end component;

  function is_rising(signal ck: std_ulogic) return boolean;
  function is_falling(signal ck: std_ulogic) return boolean;

end package clock;
