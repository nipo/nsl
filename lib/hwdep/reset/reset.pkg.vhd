library ieee;
use ieee.std_logic_1164.all;

package reset is

  component reset_at_startup is
    port(
      p_clk       : in std_ulogic;
      p_resetn    : out std_ulogic
      );
  end component;

end package reset;
