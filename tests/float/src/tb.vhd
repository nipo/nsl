library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library nsl_math, nsl_simulation, nsl_data;
use nsl_math.fixed.all;
use nsl_math.float.all;
use nsl_data.text.all;
use nsl_data.binary_io.all;
use nsl_data.endian.all;
use nsl_simulation.logging.all;
use ieee.math_real.all;

entity tb is
end tb;

architecture arch of tb is
begin

  process
    variable s : sfixed(4 downto -16);
    variable f : float32;
    variable r : real;

    file fd : binary_file;
  begin
    r := -math_pi;
    s := to_sfixed(r, s'left, s'right);
    f := to_float32(s);

    log_info("real: "
             & to_string(r)
             & ", fixed: "
             & to_string(s)
             & ", float: "
             & to_string(to_suv(f))
             & ", bin: "
             & to_hex_string(to_be(unsigned(to_suv(f))))
             );

    file_open(fd, "test.bin", WRITE_MODE);
    write(fd, to_be(unsigned(to_suv(f))));
    file_close(fd);
    wait;
  end process;
  
end;
