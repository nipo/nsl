library ieee;
use ieee.std_logic_1164.all;

-- Ultrascale+ transceiver backend body for nsl_transceiver.target. Names recognised:
--
-- - "gtrefclk0", "gtrefclk1": External clock driven by IBUFDS_GTE3/4 for the Channel PLL
-- - "gtnorthrefclk0", "gtnorthrefclk1": North-bound clock from the Quad below
-- - "gtsouthrefclk0", "gtsouthrefclk1": South-bound clock from the Quad above
-- - "stableclk": stable clock for PLL initialization, cannot be an output of
--                the transceiver, must be independent
--
-- See Ultrascale Architecture GTH Transceivers Guide for more information

package body target is

  function clock_id(name : string) return integer is
  begin
    if name = "gtrefclk0" then
      return 0;
    elsif name = "gtrefclk1" then
      return 1;
    elsif name = "gtnorthrefclk0" then
      return 2;
    elsif name = "gtnorthrefclk1" then
      return 3;
    elsif name = "gtsouthrefclk0" then
      return 4;
    elsif name = "gtsouthrefclk1" then
      return 5;
    elsif name = "stableclk" then
      return 6;
    else
      assert false
        report "nsl_transceiver.target.clock_id/gthe4: unknown clock source name '"
             & name & "'"
        severity failure;
      return -1;
    end if;
  end function;

end package body target;
