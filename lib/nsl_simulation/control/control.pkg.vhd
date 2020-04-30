library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package control is

  procedure terminate(retval : integer);
  
end package control;

package body control is

  procedure terminate(retval : integer) is
  begin
    assert false
      report "Terminating with error leve: " & integer'image(retval)
      severity failure;
  end procedure;
  
end package body control;
