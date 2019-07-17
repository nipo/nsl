library ieee;
use ieee.std_logic_1164.all;

package body clock is

  function is_rising(signal ck: std_ulogic) return boolean is
  begin
    return rising_edge(ck);
  end function is_rising;

  function is_falling(signal ck: std_ulogic) return boolean is
  begin
    return falling_edge(ck);
  end function is_falling;
  
end package body clock;
