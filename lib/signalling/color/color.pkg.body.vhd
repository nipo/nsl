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
    alias lv : rgb24_vector(1 to l'length) is l;
    alias rv : rgb24_vector(1 to r'length) is r;
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

  function "="(l, r : rgb3) return boolean is
  begin
    return l.r = r.r and l.g = r.g and l.b = r.b;
  end "=";

  function "/="(l, r : rgb3) return boolean is
  begin
    return l.r /= r.r or l.g /= r.g or l.b /= r.b;
  end "/=";

  function "="(l, r : rgb3_vector) return boolean is
    alias lv : rgb3_vector(1 to l'length) is l;
    alias rv : rgb3_vector(1 to r'length) is r;
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

  function "/="(l, r : rgb3_vector) return boolean is
  begin
    return not (l = r);
  end "/=";

  function "and"(l, r : rgb3) return rgb3 is
  begin
    return rgb3'(r => l.r and r.r,
                 g => l.g and r.g,
                 b => l.b and r.b);
  end "and";

  function "or"(l, r : rgb3) return rgb3 is
  begin
    return rgb3'(r => l.r or r.r,
                 g => l.g or r.g,
                 b => l.b or r.b);
  end "or";

  function "xor"(l, r : rgb3) return rgb3 is
  begin
    return rgb3'(r => l.r xor r.r,
                 g => l.g xor r.g,
                 b => l.b xor r.b);
  end "xor";

  function "not"(l : rgb3) return rgb3 is
  begin
    return l xor rgb3_white;
  end "not";

end package body color;
