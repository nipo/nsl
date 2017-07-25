library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package numeric is

  function log2 (x : positive) return natural;

end package numeric;

package body numeric is
    
  function log2 (x : positive) return natural is
  begin  -- log2
    if x <= 1 then
      return 0;
    else
      return log2((x+1)/2) + 1;
    end if;
  end log2;

end package body numeric;
