library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library signalling;
use signalling.diff.all;

library unisim;

entity pad_diff_input is
  generic(
    diff_term : boolean := true;
    is_clock  : boolean := false;
    invert    : boolean := false
    );
  port(
    p_diff : in diff_pair;
    p_se   : out std_ulogic
    );
end entity;

architecture rtl of pad_diff_input is
  
  signal s_se : std_ulogic;
  
begin

  if_clk: if is_clock generate
    
    diff_clk_input : unisim.vcomponents.ibufgds
      generic map (
        diff_term => diff_term
        )
      port map(
        i  => p_diff.p,
        ib => p_diff.n,
        o  => s_se
        );

  end generate;

  if_io: if (not is_clock) generate

    diff_input : unisim.vcomponents.ibufds
      generic map (
        diff_term => diff_term
        )
      port map(
        i  => p_diff.p,
        ib => p_diff.n,
        o  => s_se
        );

  end generate;
    
  p_se <= s_se when not invert else (not s_se);
  
end architecture;
