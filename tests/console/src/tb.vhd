library ieee;
use std.textio.all;

entity tb is
end tb;

architecture arch of tb is
begin

  process
    variable l : line;
  begin
    write (l, String'("Hello world!"));
    writeline (output, l);
    wait;
  end process;
  
end;
