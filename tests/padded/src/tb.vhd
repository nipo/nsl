library ieee;
use ieee.std_logic_1164.all;
use std.textio.all;

entity tb is
end entity;

architecture beh of tb is
    
    function padded(s: string; len: positive := 64; p: character := ' ') return string
    is
      alias xs: string(1 to s'length) is s;
      variable ret : string(1 to len) := (others => p);
    begin
      if xs'length >= len then
        ret := xs(1 to len);
      else
        ret(1 to xs'length) := xs;
      end if;
      return ret;
    end function;

    function describe_number(v: in integer) return string is
      variable ret: line := new string'("");
    begin
      write(ret, string'("Passed argument is: "));
      write(ret, v);
      if v >= 1000 then
        write(ret, string'(", this is a lot !"));
      end if;
      return ret.all;
    end function describe_number;

begin
    
    process  
      variable str : string(1 to 32);
    begin       
      str := padded("Hello, world", str'length, '-');
      report str;
      report describe_number(1);
      report describe_number(1000);
      wait;
    end process;
    
end architecture;
