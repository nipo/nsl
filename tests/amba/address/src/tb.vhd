library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation, nsl_amba;
use nsl_data.text.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;
use nsl_amba.address.all;

entity tb is
end tb;

architecture arch of tb is
begin

  addr: process
    constant context: log_context := "AXI4 Addr Parsing";

    constant width: natural := 32;

    procedure check_addr(a: string; value: unsigned)
    is
    begin
      assert_equal(context & " " & a, address_parse(width, a), value, FAILURE);
    end procedure;

  begin
    check_addr("x/0",          "--------------------------------"&"--------------------------------");
    check_addr("0/1",          "--------------------------------"&"0-------------------------------");
    check_addr("xe7777777/3",  "--------------------------------"&"111-----------------------------");
    check_addr("xdeadbeef/8",  "--------------------------------"&x"de"&"------------------------");
    check_addr("xde------",    "--------------------------------"&x"de"&"------------------------");
    check_addr("xdeadbeef/32", "--------------------------------"&x"deadbeef");
    check_addr(x"deadbeef",    "--------------------------------"&x"deadbeef");
    check_addr("xdead_0000",   "--------------------------------"&x"dead0000");
    check_addr(x"dead_0000",   "--------------------------------"&x"dead0000");
    check_addr("x--ad_0000/16",   "----------------------------------------"&x"ad"&"----------------");
    wait;
  end process;

end;
