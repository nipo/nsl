library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library signalling;
use signalling.diff.all;

library unisim;

entity diff_output_pad is
  generic(
    is_clock : boolean := false
    );
  port(
    p_se : in std_ulogic;
    p_diff : out diff_pair
    );
end entity;

architecture rtl of diff_output_pad is
  
begin

  se2diff: unisim.vcomponents.obufds
    port map(
      o => p_diff.p,
      ob => p_diff.n,
      i => p_se
      );
  
end architecture;
