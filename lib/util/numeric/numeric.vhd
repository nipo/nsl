package numeric is

  function log2(x : positive) return natural;
  function is_pow2(x : positive) return boolean;

end package numeric;

package body numeric is
    
  function log2(x : positive) return natural is
  begin
    if x <= 1 then
      return 0;
    else
      return log2((x+1)/2) + 1;
    end if;
  end log2;
    
  function max(x, y : natural) return natural is
  begin
    if x < y then
      return y;
    else
      return x;
    end if;
  end max;

  function min(x, y : natural) return natural is
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

end package body numeric;
