library ieee;
use ieee.std_logic_1164.all;

-- GW5A backend body for nsl_transceiver.target. Names recognised:
--
-- - "ref0", "ref1": the two chip-level differential reference
--   clock pads on the transceiver cluster.
-- - "fabric": the general-purpose fabric-input reference clock
--   the wizard labels "refin". Feeds the GTR12_QUADB's CLK_VIQ_I
--   fabric slot.
-- - "mclk": the second fabric-input alternative reference clock.
--   The name matches the wizard's convention (the "m" prefix is
--   Gowin's own label, unrelated to any MIPI block on the die).
package body target is

  function clock_id(name : string) return integer is
  begin
    if name = "ref0" then
      return 0;
    elsif name = "ref1" then
      return 1;
    elsif name = "fabric" then
      return 2;
    elsif name = "mclk" then
      return 3;
    else
      assert false
        report "nsl_transceiver.target.clock_id/gw5a: unknown clock source name '"
             & name & "'"
        severity failure;
      return -1;
    end if;
  end function;

end package body target;
