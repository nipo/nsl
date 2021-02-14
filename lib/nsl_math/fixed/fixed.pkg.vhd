library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library nsl_math;

package fixed is

  -- Fixed point data types.
  -- Type definition range bounds are important in this type.
  --
  -- Here, in both cases, x >= y, x and y are integer (posivite or negative) values.
  --
  -- ufixed(x downto y) is a value in [0    .. 2^(x+1) - 2^y] in 2^y steps.
  -- sfixed(x downto y) is a value in [-2^x .. 2^x     - 2^y] in 2^y steps.
  -- sfixed's MSB is sign bit.
  --
  -- Binary functions only handle cases where datatypes match.
  -- "resize" function may be used before using binary functions, if needed.
  --
  -- If y >= 0, behavior of these datatypes matches unsigned/signed (apart from
  -- restristions on binary functions).
  --
  -- Conversion from/to real is defined and usable at compile-time,
  -- allowing to use VHDL standard mathematical function to generate
  -- compile-time sfixed/ufixed constants.

  subtype fixed_bit is std_ulogic;
  type sfixed is array(integer range <>) of fixed_bit;
  type ufixed is array(integer range <>) of fixed_bit;

  function to_suv(value : ufixed) return std_ulogic_vector;
  function to_slv(value : ufixed) return std_logic_vector;

  function to_ufixed(value : real;
                     constant left, right : integer) return ufixed;

  function to_real(value : ufixed) return real;

  function resize(value : ufixed;
                  constant left, right : integer) return ufixed;

  function "+"(a, b: ufixed) return ufixed;
  function "-"(a, b: ufixed) return ufixed;
  function "-"(a: ufixed) return sfixed;
  function "not"(a: ufixed) return ufixed;
  function shr(a: ufixed; l : natural) return ufixed;
  function shra(a: ufixed; l : natural) return ufixed;

  function "="(a, b: ufixed) return boolean;
  function "/="(a, b: ufixed) return boolean;
  function ">"(a, b: ufixed) return boolean;
  function "<"(a, b: ufixed) return boolean;
  function ">="(a, b: ufixed) return boolean;
  function "<="(a, b: ufixed) return boolean;

  function to_suv(value : sfixed) return std_ulogic_vector;
  function to_slv(value : sfixed) return std_logic_vector;

  function to_sfixed(value : real;
                     constant left : integer;
                     constant right : integer) return sfixed;

  function to_real(value : sfixed) return real;

  function resize(value : sfixed;
                  constant left, right : integer) return sfixed;

  function "abs"(a: sfixed) return ufixed;
  function "+"(a, b: sfixed) return sfixed;
  function "-"(a, b: sfixed) return sfixed;
  function "-"(a: sfixed) return sfixed;
  function "not"(a: sfixed) return sfixed;

  function "="(a, b: sfixed) return boolean;
  function "/="(a, b: sfixed) return boolean;
  function ">"(a, b: sfixed) return boolean;
  function "<"(a, b: sfixed) return boolean;
  function ">="(a, b: sfixed) return boolean;
  function "<="(a, b: sfixed) return boolean;

end package;

package body fixed is

  constant nauf: ufixed(0 downto 1) := (others => '0');
  constant nasf: sfixed(0 downto 1) := (others => '0');

  function to_suv(value : ufixed) return std_ulogic_vector
  is
    constant v : ufixed(value'length-1 downto 0) := value;
  begin
    return std_ulogic_vector(v);
  end function;

  function to_slv(value : ufixed) return std_logic_vector
  is
    constant v : ufixed(value'length-1 downto 0) := value;
  begin
    return std_logic_vector(v);
  end function;

  function to_ufixed(value : real;
                     constant left, right : integer) return ufixed
  is
    constant sat_min : ufixed(left downto right) := (others => '0');
    constant sat_max : ufixed(left downto right) := (others => '1');
    variable ret : ufixed(left downto right);
  begin
    if value <= 0.0 then
      return sat_min;
    elsif value >= 2.0**left then
      return sat_max;
    else
      ret := ufixed(to_unsigned(integer(value * 2.0 ** (-right)), left - right + 1));
      return ret;
    end if;
  end function;

  function to_real(value : ufixed) return real
  is
    alias xv : ufixed(value'length-1 downto 0) is value;
  begin
    return real(to_integer(unsigned(xv))) * 2.0 ** real(value'right);
  end function;

  function resize(value : ufixed;
                  constant left, right : integer) return ufixed
  is
    variable ret : ufixed(left downto right);
    constant overlap_left : integer := nsl_math.arith.min(value'left, left);
    constant overlap_right : integer := nsl_math.arith.max(value'right, right);
  begin
    ret := (others => '0');

    ret(overlap_left downto overlap_right) := value(overlap_left downto overlap_right);

    return ret;
  end function;

  function shr(a: ufixed; l : natural) return ufixed
  is
    variable ret : ufixed(a'range);
    constant w : integer := a'length - l;
  begin
    ret := (others => '0');
    if w > 0 then
      ret(ret'right + w - 1 downto ret'right)
        := a(a'left downto a'left - w + 1);
    end if;
    return ret;
  end function;

  function shra(a: ufixed; l : natural) return ufixed
  is
    variable ret : ufixed(a'range);
    constant w : integer := a'length - l;
  begin
    if a(a'left) = '1' then
      ret := (others => '1');
    else
      ret := (others => '0');
    end if;
    if w > 0 then
      ret(ret'right + w - 1 downto ret'right)
        := a(a'left downto a'left - w + 1);
    end if;
    return ret;
  end function;

  function "+"(a, b: ufixed) return ufixed
  is
    variable ret : ufixed(a'range);
  begin
    if a'left /= b'left or a'right /= b'right then
      assert false
        report "Both ufixed arguments are not the same range, returning null vector"
        severity warning;
      return nauf;
    end if;

    ret := ufixed(unsigned(to_suv(a)) + unsigned(to_suv(b)));
    return ret;
  end function;

  function "-"(a, b: ufixed) return ufixed
  is
    variable ret : ufixed(a'range);
  begin
    if a'left /= b'left or a'right /= b'right then
      assert false
        report "Both ufixed arguments are not the same range, returning null vector"
        severity warning;
      return nauf;
    end if;

    ret := ufixed(unsigned(to_suv(a)) - unsigned(to_suv(b)));
    return ret;
  end function;

  function to_suv(value : sfixed) return std_ulogic_vector
  is
    constant v : sfixed(value'length-1 downto 0) := value;
  begin
    return std_ulogic_vector(v);
  end function;

  function to_slv(value : sfixed) return std_logic_vector
  is
    constant v : sfixed(value'length-1 downto 0) := value;
  begin
    return std_logic_vector(v);
  end function;

  function to_sfixed(value : real;
                     constant left : integer;
                     constant right : integer) return sfixed
  is
    variable ret : sfixed(left downto right);
  begin
    if value <= -2.0**(left-1) then
      ret := (others => '0');
      ret(ret'left) := '0';
    elsif value >= 2.0**(left-1) then
      ret := (others => '1');
    else
      ret := sfixed(to_signed(integer(value * 2.0 ** (-right)), left - right + 1));
    end if;
    return ret;
  end function;

  function to_real(value : sfixed) return real
  is
    constant v : sfixed(value'length-1 downto 0) := value;
    constant sv : signed(value'length-1 downto 0) := signed(v);
  begin
    return real(to_integer(sv)) * 2.0 ** value'right;
  end function;

  function resize(value : sfixed;
                  constant left, right : integer) return sfixed
  is
    variable ret : sfixed(left downto right);
    constant overlap_left : integer := nsl_math.arith.min(value'left, left);
    constant overlap_right : integer := nsl_math.arith.max(value'right, right);
  begin
    ret := (others => '0');

    ret(overlap_left-1 downto overlap_right) := value(overlap_left-1 downto overlap_right);
    ret(ret'left downto overlap_left) := (others => value(value'left));

    return ret;
  end function;

  function "+"(a, b: sfixed) return sfixed
  is
    variable ret : sfixed(a'range);
  begin
    if a'left /= b'left or a'right /= b'right then
      assert false
        report "Both ufixed arguments are not the same range, returning null vector"
        severity warning;
      return nasf;
    end if;

    ret := sfixed(signed(to_suv(a)) + signed(to_suv(b)));
    return ret;
  end function;

  function "-"(a, b: sfixed) return sfixed
  is
    variable ret : sfixed(a'range);
  begin
    if a'left /= b'left or a'right /= b'right then
      assert false
        report "Both ufixed arguments are not the same range, returning null vector"
        severity warning;
      return nasf;
    end if;

    ret := sfixed(signed(to_suv(a)) - signed(to_suv(b)));
    return ret;
  end function;

  function "abs"(a: sfixed) return ufixed
  is
    variable ret : sfixed(a'left+1 downto a'right);
  begin
    if a(a'left) = '1' then
      ret := -a;
    else
      ret := "0" & a;
    end if;
    return ufixed(ret);
  end function;

  function "-"(a: ufixed) return sfixed
  is
    variable ret : sfixed(a'left+1 downto a'right);
    variable lsb : sfixed(a'left+1 downto a'right);
  begin
    lsb := (others => '0');
    lsb(a'right) := '1';
    ret := sfixed(resize(a, ret'left, ret'right));
    ret := not ret + lsb;
    return ret;
  end function;

  function "-"(a: sfixed) return sfixed
  is
    variable ret : sfixed(a'left+1 downto a'right);
    variable lsb : sfixed(a'left+1 downto a'right);
  begin
    lsb := (others => '0');
    lsb(a'right) := '1';
    ret := sfixed(resize(a, ret'left, ret'right));
    ret := not ret + lsb;
    return ret;
  end function;

  function "not"(a: ufixed) return ufixed
  is
    variable ret : ufixed(a'range);
  begin
    iter: for i in a'range
    loop
      ret(i) := not a(i);
    end loop;
    return ret;
  end function;

  function "not"(a: sfixed) return sfixed
  is
    variable ret : sfixed(a'range);
  begin
    iter: for i in a'range
    loop
      ret(i) := not a(i);
    end loop;
    return ret;
  end function;

  
  function "="(a, b: ufixed) return boolean
  is
  begin
    if a'left /= b'left or a'right /= b'right then
      assert false
        report "Both ufixed arguments are not the same range, cannot compare"
        severity warning;
      return false;
    end if;

    return to_suv(a) = to_suv(b);
  end function;

  function "/="(a, b: ufixed) return boolean
  is
  begin
    if a'left /= b'left or a'right /= b'right then
      assert false
        report "Both ufixed arguments are not the same range, cannot compare"
        severity warning;
      return false;
    end if;

    return to_suv(a) /= to_suv(b);
  end function;

  function ">"(a, b: ufixed) return boolean
  is
  begin
    if a'left /= b'left or a'right /= b'right then
      assert false
        report "Both ufixed arguments are not the same range, cannot compare"
        severity warning;
      return false;
    end if;

    return unsigned(to_suv(a)) > unsigned(to_suv(b));
  end function;

  function "<"(a, b: ufixed) return boolean
  is
  begin
    if a'left /= b'left or a'right /= b'right then
      assert false
        report "Both ufixed arguments are not the same range, cannot compare"
        severity warning;
      return false;
    end if;

    return unsigned(to_suv(a)) < unsigned(to_suv(b));
  end function;

  function ">="(a, b: ufixed) return boolean
  is
  begin
    if a'left /= b'left or a'right /= b'right then
      assert false
        report "Both ufixed arguments are not the same range, cannot compare"
        severity warning;
      return false;
    end if;

    return unsigned(to_suv(a)) >= unsigned(to_suv(b));
  end function;

  function "<="(a, b: ufixed) return boolean
  is
  begin
    if a'left /= b'left or a'right /= b'right then
      assert false
        report "Both ufixed arguments are not the same range, cannot compare"
        severity warning;
      return false;
    end if;

    return unsigned(to_suv(a)) <= unsigned(to_suv(b));
  end function;

  
  function "="(a, b: sfixed) return boolean
  is
  begin
    if a'left /= b'left or a'right /= b'right then
      assert false
        report "Both sfixed arguments are not the same range, cannot compare"
        severity warning;
      return false;
    end if;

    return to_suv(a) = to_suv(b);
  end function;

  function "/="(a, b: sfixed) return boolean
  is
  begin
    if a'left /= b'left or a'right /= b'right then
      assert false
        report "Both sfixed arguments are not the same range, cannot compare"
        severity warning;
      return false;
    end if;

    return to_suv(a) /= to_suv(b);
  end function;

  function ">"(a, b: sfixed) return boolean
  is
  begin
    if a'left /= b'left or a'right /= b'right then
      assert false
        report "Both sfixed arguments are not the same range, cannot compare"
        severity warning;
      return false;
    end if;

    return signed(to_suv(a)) > signed(to_suv(b));
  end function;

  function "<"(a, b: sfixed) return boolean
  is
  begin
    if a'left /= b'left or a'right /= b'right then
      assert false
        report "Both sfixed arguments are not the same range, cannot compare"
        severity warning;
      return false;
    end if;

    return signed(to_suv(a)) < signed(to_suv(b));
  end function;

  function ">="(a, b: sfixed) return boolean
  is
  begin
    if a'left /= b'left or a'right /= b'right then
      assert false
        report "Both sfixed arguments are not the same range, cannot compare"
        severity warning;
      return false;
    end if;

    return signed(to_suv(a)) >= signed(to_suv(b));
  end function;

  function "<="(a, b: sfixed) return boolean
  is
  begin
    if a'left /= b'left or a'right /= b'right then
      assert false
        report "Both sfixed arguments are not the same range, cannot compare"
        severity warning;
      return false;
    end if;

    return signed(to_suv(a)) <= signed(to_suv(b));
  end function;

end package body;
