library ieee;
use ieee.std_logic_1164.all;

library unisim;
library signalling;

entity pad_diff_clock_input is
  port(
    p_pad : in  signalling.diff.diff_pair;
    p_clk : out signalling.diff.diff_pair
    );
end entity;

architecture sp6 of pad_diff_clock_input is

begin

  inst: unisim.vcomponents.ibufgds_diff_out
   port map (
     i => p_pad.p,
     ib => p_pad.n,
     o => p_clk.p,
     ob => p_clk.n
     );

end architecture;
