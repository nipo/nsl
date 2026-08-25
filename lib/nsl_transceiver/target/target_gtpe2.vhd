library ieee;
use ieee.std_logic_1164.all;

-- Series 7 GTP transceiver backend body for nsl_transceiver.target. Names recognised:
--
-- - "gtrefclk0", "gtrefclk1": the two main reference clocks on the chip
-- - "gtwestrefclk0", "gtwestrefclk1": west-side reference clocks
-- - "gteastrefclk0", "gteastrefclk1": east-side reference clocks
-- - "stableclk": stable clock for PLL initialization, cannot be an output of
--                the transceiver, must be independent
--
-- See UG482 for more information

package body target is

  function clock_id(name : string) return integer is
  begin
    if name = "gtrefclk0" then
      return 0;
    elsif name = "gtrefclk1" then
      return 1;
    elsif name = "gtwestrefclk0" then
      return 2;
    elsif name = "gtwestrefclk1" then
      return 3;
    elsif name = "gteastrefclk0" then
      return 4;
    elsif name = "gteastrefclk1" then
      return 5;
    elsif name = "stableclk" then
      return 6;
    else
      assert false
        report "nsl_transceiver.target.clock_id/gtpe2: unknown clock source name '"
             & name & "'"
        severity failure;
      return -1;
    end if;
  end function;

end package body target;
