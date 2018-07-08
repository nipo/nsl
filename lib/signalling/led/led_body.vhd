library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package body led is

  function "="(l, r : led_rgb8) return boolean is
  begin
    return l.r = r.r and l.g = r.g and l.b = r.b;
  end "=";

  function "/="(l, r : led_rgb8) return boolean is
  begin
    return l.r /= r.r or l.g /= r.g or l.b /= r.b;
  end "/=";

  function "="(l, r : led_rgb8_vector) return boolean is
    alias lv : led_rgb8_vector(1 to l'length ) is l;
    alias rv : led_rgb8_vector(1 to r'length ) is r;
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

  function "/="(l, r : led_rgb8_vector) return boolean is
  begin
    return not (l = r);
  end "/=";
  
end package body led;
