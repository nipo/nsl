library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library work;
use work.rgb.all;

-- YCbCr color encoding.
package ycbcr is

  type ycbcr24 is record
    y : unsigned(7 downto 0);
    cb, cr : signed(7 downto 0);
  end record;

  type ycbcr24_vector is array(natural range <>) of ycbcr24;

  function "="(l, r : ycbcr24) return boolean;
  function "/="(l, r : ycbcr24) return boolean;
  function "="(l, r : ycbcr24_vector) return boolean;
  function "/="(l, r : ycbcr24_vector) return boolean;

  function to_ycbcr24(y, cb, cr: real) return ycbcr24;

  type ycbcr_conversion_mode_t is (
    YCBCR_BT601,
    YCBCR_BT709,
    YCBCR_BT2020_CST,
    YCBCR_BT2020_NCST
    );
  
  function to_ycbcr24(rgb: rgb24;
                      mode: ycbcr_conversion_mode_t := YCBCR_BT601) return ycbcr24;
  
end package ycbcr;

package body ycbcr is

  function "="(l, r : ycbcr24) return boolean is
  begin
    return l.y = r.y and l.cb = r.cb and l.cr = r.cr;
  end "=";

  function "/="(l, r : ycbcr24) return boolean is
  begin
    return l.y /= r.y or l.cb /= r.cb or l.cr /= r.cr;
  end "/=";

  function "="(l, r : ycbcr24_vector) return boolean is
    alias lv : ycbcr24_vector(1 to l'length) is l;
    alias rv : ycbcr24_vector(1 to r'length) is r;
    variable result : boolean;
  begin
    t: if l'length /= r'length THEN
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

  function "/="(l, r : ycbcr24_vector) return boolean is
  begin
    return not (l = r);
  end "/=";

  function clamp(x, v, y : real) return real
  is
  begin
    if x > v then
      return x;
    elsif v > y then
      return y;
    else
      return v;
    end if;
  end function;

  function to_ycbcr24(y, cb, cr : real) return ycbcr24
  is
    variable ret : ycbcr24;
  begin
    ret.y := to_unsigned(integer(clamp(0.0, y, 1.0) * 255.0), 8);
    ret.cr := to_signed(integer(clamp(-1.0, cr, 127.0 / 128.0) * 128.0), 8);
    ret.cb := to_signed(integer(clamp(-1.0, cb, 127.0 / 128.0) * 128.0), 8);

    return ret;
  end function;

  function to_ycbcr24(rgb: rgb24;
                      mode: ycbcr_conversion_mode_t := YCBCR_BT601) return ycbcr24
  is
    variable ret: ycbcr24;
    variable r, g, b, y, cb, cr : real;
  begin
    r := real(to_integer(rgb.r));
    g := real(to_integer(rgb.g));
    b := real(to_integer(rgb.b));

    case mode is
      when YCBCR_BT601 =>
        y := 0.299 * r + 0.587 * g + 0.114 * b;
        cr := (r - y) * 0.71327;
        cb := (b - y) * 0.56433;

      when YCBCR_BT709 =>
        y := 0.2126 * r + 0.7152 * g + 0.0722 * b;
        cr := (r - y) * 1.5748;
        cb := (b - y) * 1.8556;

      when YCBCR_BT2020_CST =>
        y := 0.2627 * r + 0.6780 * g + 0.0593 * b;
        cr := r - y;
        if -0.8592 <= cr and cr <= 0.0 then
          cr := cr / 1.7184;
        else
          cr := cr / 0.9936;
        end if;
        cb := b - y;
        if -0.9702 <= cb and cb <= 0.0 then
          cb := cb / 1.9404;
        else
          cb := cb / 1.5816;
        end if;

      when YCBCR_BT2020_NCST =>
        y := 0.2627 * r + 0.6780 * g + 0.0593 * b;
        cr := (r - y) * 1.4746;
        cb := (b - y) * 1.8814;
    end case;


    return to_ycbcr24(y, cb, cr);
  end function;

end package body ycbcr;
