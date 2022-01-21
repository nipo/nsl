library work;

package int_ext is

  type integer_vector is array (integer range <>) of integer;
  function max(v : integer_vector;
               default : integer := integer'low) return integer;
  function min(v : integer_vector;
               default : integer := integer'high) return integer;

end package int_ext;

package body int_ext is

  function max(v : integer_vector;
               default : integer := integer'low) return integer is
    variable ret : integer := default;
  begin
    for i in v'range
    loop
      ret := work.arith.max(v(i), ret);
    end loop;
    return ret;
  end function;
    
  function min(v : integer_vector;
               default : integer := integer'high) return integer is
    variable ret : integer := default;
  begin
    for i in v'range
    loop
      ret := work.arith.min(v(i), ret);
    end loop;
    return ret;
  end function;

end package body int_ext;
