library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package body color is

  function "="(l, r : rgb24) return boolean is
  begin
    return l.r = r.r and l.g = r.g and l.b = r.b;
  end "=";

  function "/="(l, r : rgb24) return boolean is
  begin
    return l.r /= r.r or l.g /= r.g or l.b /= r.b;
  end "/=";

  function "="(l, r : rgb24_vector) return boolean is
    alias lv : rgb24_vector(1 to l'length ) is l;
    alias rv : rgb24_vector(1 to r'length ) is r;
    variable result : boolean;
  begin
    t: if l'length /= r'length THEN
      assert false
        report "Vectors of differing sizes passed"
        severity failure;
      result := false;
    else
      result := true;
      fe: for i in lv'range loop
        result := result and (lv(i) = rv(i));
      end loop;
    end if;

    return result;
  end "=";

  function "/="(l, r : rgb24_vector) return boolean is
  begin
    return not (l = r);
  end "/=";
  
end package body color;
