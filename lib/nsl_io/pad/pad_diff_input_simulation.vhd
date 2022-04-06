library ieee;
use ieee.std_logic_1164.all;

library nsl_io;
use nsl_io.diff.all;

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

architecture sim of pad_diff_input is
  
  signal s_se : std_ulogic;
  
begin

  s_se <= p_diff.p and not p_diff.n;
  p_se <= s_se when not invert else (not s_se);
  
end architecture;
