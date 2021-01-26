library ieee;
use ieee.std_logic_1164.all;

package logic is

  function popcnt(v : std_ulogic_vector) return integer;

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

end package body logic;
