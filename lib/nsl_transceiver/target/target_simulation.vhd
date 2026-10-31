library ieee;
use ieee.std_logic_1164.all;

-- Simulation backend body for nsl_transceiver.target. The vocabulary
-- is deliberately a superset of what the real targets recognise, so a
-- design written against any of them can be simulated without having
-- its clock names rewritten:
--
-- - "ref0" to "ref3": reference clocks arriving on a pad, the
--   transceiver's own. "gtrefclk0" and "gtrefclk1" name the first
--   two under the Xilinx spelling.
-- - "fabric", "mclk": reference clocks arriving from the fabric,
--   under the two names the Gowin wizard uses.
-- - "stableclk": the housekeeping clock, which runs regardless of
--   the transceiver and is therefore the one a reset sequencer or a
--   configuration bus is timed on.
package body target is

  function clock_id(name : string) return integer is
  begin
    if name = "ref0" or name = "gtrefclk0" then
      return 0;
    elsif name = "ref1" or name = "gtrefclk1" then
      return 1;
    elsif name = "ref2" then
      return 2;
    elsif name = "ref3" then
      return 3;
    elsif name = "fabric" then
      return 4;
    elsif name = "mclk" then
      return 5;
    elsif name = "stableclk" then
      return 6;
    else
      assert false
        report "nsl_transceiver.target.clock_id/simulation: unknown clock source name '"
             & name & "'"
        severity failure;
      return -1;
    end if;
  end function;

end package body target;
