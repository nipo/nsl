library ieee;
use ieee.std_logic_1164.all;

-- Series 7 SERDES backend body for nsl_transceiver.target
-- Only one reference clock name is accepted since the backend
-- only needs one reference clock 

package body target is

  function clock_id(name : string) return integer is
  begin
    if name = "refclk0" then
      return 0;
    else
      assert false
        report "nsl_transceiver.target.clock_id/series7_serdes: unknown clock source name '"
             & name & "'"
        severity failure;
      return -1;
    end if;
  end function;

end package body target;
