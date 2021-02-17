package arith is

  function log2(x : positive) return natural;
  function is_pow2(x : positive) return boolean;
  function max(x, y : integer) return integer;
  function min(x, y : integer) return integer;
  function gcd(x, y : integer) return integer;
  function lcm(x, y : integer) return integer;

end package arith;

package body arith is
    
  function log2(x : positive) return natural is
  begin
    if x <= 1 then
      return 0;
    else
      return log2((x+1)/2) + 1;
    end if;
  end log2;
    
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

  function is_pow2(x : positive) return boolean is
  begin
    if x < 2 then
      return true;
    elsif x mod 2 /= 0 then
      return false;
    else
      return is_pow2(x / 2);
    end if;
  end is_pow2;

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
