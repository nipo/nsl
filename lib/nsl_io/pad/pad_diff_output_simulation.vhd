library ieee;
use ieee.std_logic_1164.all;

library nsl_io;
use nsl_io.diff.all;

entity pad_diff_output is
  generic(
    is_clock : boolean := false
    );
  port(
    p_se : in std_ulogic;
    p_diff : out diff_pair
    );
end entity;

architecture sim of pad_diff_output is
  
begin

  p_diff <= to_diff(p_se);
  
end architecture;
