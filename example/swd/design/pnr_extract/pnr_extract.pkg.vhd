library ieee;
use ieee.std_logic_1164.all;

package pnr_extract is
  component swd_main is
    port (
      led: out std_logic;
      swclk : in std_logic;
      swdio : inout std_logic
      );
  end component;
end package;
