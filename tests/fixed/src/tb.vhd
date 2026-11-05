library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library nsl_math, nsl_simulation, nsl_data;
use nsl_math.fixed.all;
use nsl_data.text.all;
use nsl_simulation.logging.all;
use nsl_simulation.control.all;
use ieee.math_real.all;

entity tb is
end tb;

architecture arch of tb is
begin

  process
    procedure check(what: string;
                    got, expected: std_ulogic_vector) is
    begin
      assert got = expected
        report what & ": got " & to_string(got)
        & ", expected " & to_string(expected)
        severity failure;
    end procedure;

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
    
    check("to_sfixed in range", to_suv(to_sfixed(7.5, 3, -2)), "011110");
    check("to_sfixed negative", to_suv(to_sfixed(-1.25, 3, -2)), "111011");
    check("to_sfixed zero", to_suv(to_sfixed(0.0, 3, -2)), "000000");
    check("to_sfixed lowest", to_suv(to_sfixed(-8.0, 3, -2)), "100000");
    check("to_sfixed highest", to_suv(to_sfixed(7.75, 3, -2)), "011111");
    check("to_sfixed underflow", to_suv(to_sfixed(-100.0, 3, -2)), "100000");
    check("to_sfixed overflow", to_suv(to_sfixed(100.0, 3, -2)), "011111");
    check("to_sfixed wide",
          to_suv(to_sfixed(-(2.0 ** 40) + 1.0, 47, 0)),
          std_ulogic_vector(shift_left(to_signed(-1, 48), 40) + 1));

    check("to_ufixed in range", to_suv(to_ufixed(5.25, 3, -2)), "010101");
    check("to_ufixed underflow", to_suv(to_ufixed(-1.0, 3, -2)), "000000");
    check("to_ufixed overflow", to_suv(to_ufixed(100.0, 3, -2)), "111111");
    check("to_ufixed wide",
          to_suv(to_ufixed(2.0 ** 40 + 1.0, 47, 0)),
          std_ulogic_vector(shift_left(to_unsigned(1, 48), 40) + 1));

    check("resize_saturate sfixed overflow",
          to_suv(resize_saturate(to_sfixed(100.0, 7, 0), 3, 0)), "0111");
    check("resize_saturate sfixed underflow",
          to_suv(resize_saturate(to_sfixed(-100.0, 7, 0), 3, 0)), "1000");
    check("resize_saturate ufixed overflow",
          to_suv(resize_saturate(to_ufixed(100.0, 7, 0), 3, 0)), "1111");

    terminate(0);
  end process;
  
end;
