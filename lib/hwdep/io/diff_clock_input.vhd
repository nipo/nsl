library ieee;
use ieee.std_logic_1164.all;

library unisim;
use unisim.vcomponents.all;

library signalling;

entity diff_clock_input is
  port(
    p_i : in  signalling.diff.diff_pair;
    p_o : out signalling.diff.diff_pair
    );
end entity;

architecture sp6 of diff_clock_input is

  signal clk: std_ulogic;

begin

  inst: ibufgds
   port map (
     i => p_i.p,
     ib => p_i.n,
     o => clk
     );

  p_o.p <= clk;
  p_o.n <= not clk;

end architecture;
