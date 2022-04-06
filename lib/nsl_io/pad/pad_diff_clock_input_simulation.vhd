library ieee;
use ieee.std_logic_1164.all;

library nsl_io;

entity pad_diff_clock_input is
  generic(
    diff_term : boolean := true;
    invert    : boolean := false
    );
  port(
    p_pad : in  nsl_io.diff.diff_pair;
    p_clk : out nsl_io.diff.diff_pair
    );
end entity;

architecture sim of pad_diff_clock_input is

begin

  p_clk <= nsl_io.diff.swap(p_pad, invert);
  
end architecture;
