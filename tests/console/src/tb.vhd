library ieee;
use std.textio.all;


library nsl_simulation;
use nsl_simulation.control.all;
entity tb is
end tb;

architecture arch of tb is
begin

  process
    variable l : line;
  begin
    write (l, String'("Hello world!"));
    writeline (output, l);
    terminate(0);
  end process;
  
end;
