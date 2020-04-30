library nsl_math;

package gf2 is

  subtype gf2_element is bit;
  type gf2_vector is array(natural range <>) of gf2_element;

  function shift_left(arg: gf2_vector; count: natural) return gf2_vector;
  function shift_right(arg: gf2_vector; count: natural) return gf2_vector;
  function resize(arg: gf2_vector; new_size: natural) return gf2_vector;
  function "+"(x, y : gf2_vector) return gf2_vector;
  function "-"(x, y : gf2_vector) return gf2_vector;
  function "*"(x, y : gf2_vector) return gf2_vector;
  function "mod"(num, denom: gf2_vector) return gf2_vector;
  --function exp(x : gf2_vector, n : unsigned) return gf2_vector;
  
end package gf2;

package body gf2 is

  use nsl_math.arith.min;
  use nsl_math.arith.max;
  
  constant gf2_null: gf2_vector(0 downto 1) := (others => '0');

  function gf2sl(arg: gf2_vector; count: natural) return gf2_vector is
    constant arg_l: integer := arg'length-1;
    alias xarg: gf2_vector(arg_l downto 0) is arg;
    variable result: gf2_vector(arg_l downto 0) := (others => '0');
  begin
    if count <= arg_l then
      result(arg_l downto count) := xarg(arg_l-count downto 0);
    end if;
    return result;
  end gf2sl;

  function gf2sr(arg: gf2_vector; count: natural) return gf2_vector is
    constant arg_l: integer := arg'length-1;
    alias xarg: gf2_vector(arg_l downto 0) is arg;
    variable result: gf2_vector(arg_l downto 0) := (others => '0');
  begin
    if count <= arg_l then
      result(arg_l-count downto 0) := xarg(arg_l downto count);
    end if;
    return result;
  end gf2sr;

  function shift_left(arg: gf2_vector; count: natural) return gf2_vector is
  begin
    if arg'length < 1 then
      return gf2_null;
    end if;

    return gf2sl(arg, count);
  end shift_left;

  function shift_right(arg: gf2_vector; count: natural) return gf2_vector is
  begin
    if arg'length < 1 then
      return gf2_null;
    end if;

    return gf2sr(arg, count);
  end shift_right;

  function resize(arg: gf2_vector; new_size: natural) return gf2_vector is
    constant arg_left: integer := arg'length-1;
    alias xarg: gf2_vector(arg_left downto 0) is arg;
    variable result: gf2_vector(new_size-1 downto 0) := (others => '0');
  begin
    if new_size < 1 then
      return gf2_null;
    end if;

    if arg'length = 0 then
      return result;
    end if;
    
    if result'length < arg'length then
      result(result'left downto 0) := xarg(result'left downto 0);
    else
      result(result'left downto xarg'left+1) := (others => '0');
      result(xarg'left downto 0) := xarg;
    end if;

    return result;
  end resize;

  function "+"(x, y : gf2_vector) return gf2_vector is
    constant size: natural := max(x'length, y'length);
    variable xn : gf2_vector(size-1 downto 0) := resize(x, size);
    variable yn : gf2_vector(size-1 downto 0) := resize(y, size);
    variable ret : gf2_vector(size-1 downto 0);
  begin
    for i in 0 to size-1 loop
      ret(i) := xn(i) xor yn(i);
    end loop;
    return ret;
  end function;

  function "-"(x, y : gf2_vector) return gf2_vector is
  begin
    return x + y;
  end function;

  function "*"(x, y : gf2_vector) return gf2_vector is
    constant size: natural := x'length + y'length - 1;
    variable s : gf2_vector(size-1 downto 0) := resize(y, size);
    variable acc : gf2_vector(size-1 downto 0);
  begin
    for i in 0 to x'length-1 loop
      if x(x'low + i) = '1' then
        acc := acc + s;
      end if;
      s := shift_left(s, 1);
    end loop;

    return acc;
  end function;

  function "mod"(num, denom: gf2_vector) return gf2_vector is
    alias xnum: gf2_vector(num'length-1 downto 0) is num;
    alias xdenom: gf2_vector(denom'length-1 downto 0) is denom;

    variable s : gf2_vector(num'length-1 downto 0);
    variable acc : gf2_vector(num'length-1 downto 0);
  begin
    assert denom(denom'high) = '1'
      report "Denominator MSB must be 1"
      severity failure;

    if num'length < denom'length then
      return resize(num, denom'length - 1);
    end if;

    s := shift_left(resize(denom, num'length), num'length - denom'length);
    acc := xnum;
    for i in num'length downto denom'length
    loop
      if acc(i) = '1' then
        acc := acc - s;
      end if;
      s := shift_right(s, 1);
    end loop;
        
    return resize(acc, denom'length - 1);
  end function;

end package body gf2;
