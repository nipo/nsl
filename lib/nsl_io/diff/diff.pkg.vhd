library ieee;
use ieee.std_logic_1164.all;

package diff is

  type diff_pair is record
    p : std_ulogic;
    n : std_ulogic;
  end record;

  type diff_pair_vector is array(natural range <>) of diff_pair;

  function to_diff(v: std_ulogic) return diff_pair;
  function to_se(d: diff_pair) return std_ulogic;

end package diff;

package body diff is

  function to_diff(v: std_ulogic) return diff_pair
  is
    variable ret : diff_pair;
  begin
    ret.p := v;
    ret.n := not v;
    return ret;
  end function;

  function to_se(d: diff_pair) return std_ulogic
  is
  begin
    return d.p;
  end function;

end package body diff;
