library ieee;
use ieee.std_logic_1164.all;
use std.textio.all;

library nsl_math, nsl_simulation;
use nsl_math.fixed.all;
use nsl_data.text.all;
use nsl_simulation.logging.all;
use ieee.math_real.all;

entity tb is
end tb;

architecture arch of tb is
begin

  process
    variable s : sfixed(4 downto -16);
    variable sr : sfixed(3 downto -8);
    variable sr2 : sfixed(8 downto -3);
    variable r : real;
  begin
    s := to_sfixed(-math_pi, 4, -16);
    sr := resize(s, sr'left, sr'right);
    sr2 := resize(sr, sr2'left, sr2'right);
    r := to_real(sr2);

    log_info("Fixed: "
             & to_string(s)
             & ", fixed resized: "
             & to_string(sr)
             & ", fixed resized2: "
             & to_string(sr2)
             & ", abs resized2: "
             & to_string(abs(sr2))
             & ", real: "
             & to_string(r));
    
    wait;
  end process;
  
end;
