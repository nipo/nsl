library ieee;
use ieee.std_logic_1164.all;

package logic is

  function popcnt(v : std_ulogic_vector) return integer;
  function xor_reduce(x : std_ulogic_vector) return std_ulogic;
  function and_reduce(x : std_ulogic_vector) return std_ulogic;
  function or_reduce(x : std_ulogic_vector) return std_ulogic;

end package logic;

package body logic is

  function popcnt(v : std_ulogic_vector) return integer
  is
    variable r : integer;
  begin
    r := 0;

    for i in v'range
    loop
      if to_x01(v(i)) = '1' then
        r := r + 1;
      end if;
    end loop;

    return r;
  end function;
    
  function xor_reduce(x : std_ulogic_vector) return std_ulogic is
    variable ret : std_ulogic;
  begin
    ret := '0';

    for i in x'range
    loop
      ret := ret xor x(i);
    end loop;

    return ret;
  end xor_reduce;

  function and_reduce(x : std_ulogic_vector) return std_ulogic is
    variable ret : std_ulogic;
  begin
    ret := '0';

    for i in x'range
    loop
      ret := ret and x(i);
    end loop;

    return ret;
  end and_reduce;

  function or_reduce(x : std_ulogic_vector) return std_ulogic is
    variable ret : std_ulogic;
  begin
    ret := '0';

    for i in x'range
    loop
      ret := ret or x(i);
    end loop;

    return ret;
  end or_reduce;

end package body logic;
