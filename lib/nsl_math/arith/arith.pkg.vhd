library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package arith is

  -- Returns y such that 2**y <= x
  -- e.g. for x=9..16, this returns 4
  function log2(x : natural) return natural;

  function is_pow2(x : natural) return boolean;
  function max(x, y : integer) return integer;
  function min(x, y : integer) return integer;
  -- Greatest comon divisor between two integers
  function gcd(x, y : integer) return integer;
  -- Least common multiple between two integers.
  function lcm(x, y : integer) return integer;
  -- Aligns number to next power of two.
  -- Returns x if x is a power of two.
  -- Return 1 if x is 0.
  function align_up(x: natural) return natural;

  -- Returns the unsigned constant that has the right size to express
  -- x as unsigned.
  function to_unsigned_auto(value : natural) return unsigned;
  -- Returns the signed constant that has the right size to express
  -- x as signed.
  function to_signed_auto(value : integer) return signed;

  -- Returns the unsigned maximum value for a given length.
  function unsigned_max(length : natural) return unsigned;
  -- Returns the unsigned minimum (0) for a given length.
  function unsigned_min(length : natural) return unsigned;

  -- Returns the signed maximum value for a given length.
  function signed_max(length : natural) return signed;
  -- Returns the signed minimum value for a given length.
  function signed_min(length : natural) return signed;

end package arith;

package body arith is
    
  function log2(x : natural) return natural is
  begin
    if x <= 1 then
      return 0;
    else
      return log2((x+1)/2) + 1;
    end if;
  end log2;

  function to_unsigned_auto(value : natural) return unsigned is
    constant width_c: natural := log2(value+1);
    variable ret: unsigned(width_c-1 downto 0) := to_unsigned(value, width_c);
  begin
    return ret;
  end to_unsigned_auto;

  function signed_left(value : integer) return integer
  is
  begin
    if value = 0 then
      return 0;
    elsif value < 0 then
      return log2(-value);
    else
      return log2(value+1);
    end if;
  end function;

  function to_signed_auto(value : integer) return signed is
    constant ret: signed(signed_left(value) downto 0)
      := to_signed(value, signed_left(value)+1);
  begin
    return ret;
  end to_signed_auto;

  function unsigned_max(length : natural) return unsigned
  is
    constant ret : unsigned(length-1 downto 0) := (others => '1');
  begin
    return ret;
  end function;

  function unsigned_min(length : natural) return unsigned
  is
    constant ret : unsigned(length-1 downto 0) := (others => '0');
  begin
    return ret;
  end function;

  function signed_max(length : natural) return signed
  is
    variable ret : signed(length-1 downto 0);
  begin
    ret := (others => '1');
    ret(ret'left) := '0';
    return ret;
  end function;

  function signed_min(length : natural) return signed
  is
    variable ret : signed(length-1 downto 0);
  begin
    ret := (others => '0');
    ret(ret'left) := '1';
    return ret;
  end function;

  function max(x, y : integer) return integer is
  begin
    if x < y then
      return y;
    else
      return x;
    end if;
  end max;

  function min(x, y : integer) return integer is
  begin
    if x < y then
      return x;
    else
      return y;
    end if;
  end min;

  function is_pow2(x : natural) return boolean is
  begin
    if x < 2 then
      return true;
    elsif x mod 2 /= 0 then
      return false;
    else
      return is_pow2(x / 2);
    end if;
  end is_pow2;

  function align_up(x: natural) return natural
  is
  begin
    return 2 ** log2(x);
  end function;

  function gcd(x, y : integer) return integer is
  begin
    if y < x then
      return gcd(y, x);
    end if;

    -- x <= y, always

    if x = y or x = 0 then
      return y;
    end if;

    if (x mod 2) = 0 then
      if (y mod 2) = 0 then
        return 2 * gcd(x / 2, y / 2);
      else
        return gcd(x / 2, y);
      end if;
    else
      if (y mod 2) = 0 then
        return gcd(x, y / 2);
      else
        return gcd((y - x) / 2, x);
      end if;
    end if;
  end function;

  function lcm(x, y : integer) return integer is
  begin
    return x / gcd(x, y) * y;
  end function;
  
end package body arith;
