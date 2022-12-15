library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
library nsl_data;

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

  function to_x01(value : ufixed) return ufixed;
  function to_x01(value : sfixed) return sfixed;
  function to_01(value : ufixed) return ufixed;
  function to_01(value : sfixed) return sfixed;
  function to_suv(value : ufixed) return std_ulogic_vector;
  function to_slv(value : ufixed) return std_logic_vector;
  function to_unsigned(value : ufixed) return unsigned;
  function to_unsigned(value : sfixed) return unsigned;
  function to_signed(value : sfixed) return signed;
  function sign(value : sfixed) return std_ulogic;

  function to_ufixed(value : real;
                     constant left, right : integer) return ufixed;
  function to_ufixed_auto(value : real;
                          constant length : integer) return ufixed;
  function to_sfixed_auto(value : real;
                          constant length : integer) return sfixed;
  function ufixed_left(value : real;
                          constant length : integer) return integer;
  function ufixed_right(value : real;
                           constant length : integer) return integer;
  function sfixed_left(value : real;
                          constant length : integer) return integer;
  function sfixed_right(value : real;
                           constant length : integer) return integer;

  function to_ufixed_saturate(s: sfixed;
                              constant left, right : integer) return ufixed;
  function to_sfixed(u: ufixed) return sfixed;
  function to_sfixed_scaled(u: ufixed) return sfixed;
  function to_ufixed_scaled(s: sfixed) return ufixed;

  function to_real(value : ufixed) return real;

  function resize(value : ufixed;
                  constant left, right : integer) return ufixed;
  function resize_saturate(value : ufixed;
                           constant left, right : integer) return ufixed;

  function "+"(a, b: ufixed) return ufixed;
  function mul(a, b: ufixed;
               constant left, right : integer) return ufixed;
  function mul(a: sfixed; b: ufixed;
               constant left, right : integer) return sfixed;
  function mul(a, b: sfixed;
               constant left, right : integer) return sfixed;
  function "-"(a, b: ufixed) return ufixed;
  function sub_saturate(a, b: ufixed) return sfixed;
  function "-"(a: ufixed) return ufixed;
  function "not"(a: ufixed) return ufixed;
  function shr(a: ufixed; l : natural) return ufixed;
  function shra(a: ufixed; l : natural) return ufixed;
  function shr(a: sfixed; l : natural) return sfixed;

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
  function resize_saturate(value : sfixed;
                           constant left, right : integer) return sfixed;

  function "abs"(a: sfixed) return ufixed;
  function "+"(a, b: sfixed) return sfixed;
  function add_saturate(a, b: sfixed) return sfixed;
  -- Add with one extra bit on the output to avoid overflows
  function add_extend(a, b: sfixed) return sfixed;
  function "-"(a, b: sfixed) return sfixed;
  function sub_extend(a, b: sfixed) return sfixed;
  function "-"(a: sfixed) return sfixed;
  function neg_extend(a: sfixed) return sfixed;
  function "not"(a: sfixed) return sfixed;

  function "="(a, b: sfixed) return boolean;
  function "/="(a, b: sfixed) return boolean;
  function ">"(a, b: sfixed) return boolean;
  function "<"(a, b: sfixed) return boolean;
  function ">="(a, b: sfixed) return boolean;
  function "<="(a, b: sfixed) return boolean;

  function "="(a: sfixed; b: real) return boolean;
  function "/="(a: sfixed; b: real) return boolean;
  function ">"(a: sfixed; b: real) return boolean;
  function "<"(a: sfixed; b: real) return boolean;
  function ">="(a: sfixed; b: real) return boolean;
  function "<="(a: sfixed; b: real) return boolean;

  function "="(a: ufixed; b: real) return boolean;
  function "/="(a: ufixed; b: real) return boolean;
  function ">"(a: ufixed; b: real) return boolean;
  function "<"(a: ufixed; b: real) return boolean;
  function ">="(a: ufixed; b: real) return boolean;
  function "<="(a: ufixed; b: real) return boolean;

  function to_string(value: sfixed) return string;
  function to_string(value: ufixed) return string;
  
  constant nauf: ufixed(0 downto 1) := (others => '0');
  constant nasf: sfixed(0 downto 1) := (others => '0');

end package;

package body fixed is

  use nsl_data.text.all;

  function sign(value : sfixed) return std_ulogic
  is
  begin
    if value'length > 0 then
      return value(value'left);
    end if;
    return '0';
  end function;

  function ufixed_left(value : real;
                          constant length : integer) return integer
  is
  begin
    if value <= 0.0 then
      return 0;
    else
      return integer(floor(log2(value)));
    end if;
  end function;

  function ufixed_right(value : real;
                           constant length : integer) return integer
  is
  begin
    return ufixed_left(value, length) - length + 1;
  end function;

  function sfixed_left(value : real;
                          constant length : integer) return integer
  is
  begin
    if value = 0.0 then
      return 1;
    elsif value < -0.0 then
      return integer(floor(log2(-value))) + 1;
    else
      return integer(floor(log2(value))) + 1;
    end if;
  end function;

  function sfixed_right(value : real;
                        constant length : integer) return integer
  is
  begin
    return sfixed_left(value, length) - length + 1;
  end function;

  function to_ufixed_auto(value : real;
                          constant length : integer) return ufixed
  is
    constant ret: ufixed(ufixed_left(value, length) downto ufixed_right(value, length))
      := to_ufixed(value, ufixed_left(value, length), ufixed_right(value, length));
  begin
    return ret;
  end function;
  
  function to_sfixed_auto(value : real;
                          constant length : integer) return sfixed
  is
    constant ret: sfixed(sfixed_left(value, length) downto sfixed_right(value, length))
      := to_sfixed(value, sfixed_left(value, length), sfixed_right(value, length));
  begin
    return ret;
  end function;

  function to_x01(value : ufixed) return ufixed
  is
    constant ret: ufixed(value'left downto value'right) := ufixed(to_x01(to_suv(value)));
  begin
    return ret;
  end function;

  function to_x01(value : sfixed) return sfixed
  is
    constant ret: sfixed(value'left downto value'right) := sfixed(to_x01(to_suv(value)));
  begin
    return ret;
  end function;

  function to_01(value : ufixed) return ufixed
  is
    variable ret: ufixed(value'left downto value'right);
  begin
    for i in value'range
    loop
      if value(i) = '1' then
        ret(i) := '1';
      else
        ret(i) := '0';
      end if;
    end loop;

    return ret;
  end function;

  function to_01(value : sfixed) return sfixed
  is
    variable ret: sfixed(value'left downto value'right);
  begin
    for i in value'range
    loop
      if value(i) = '1' then
        ret(i) := '1';
      else
        ret(i) := '0';
      end if;
    end loop;

    return ret;
  end function;

  function to_suv(value : ufixed) return std_ulogic_vector
  is
    constant v : ufixed(value'length downto 1) := value;
    constant vu : std_ulogic_vector(value'length downto 1) := std_ulogic_vector(v);
  begin
    if v'length <= 0 then
      return "";
    end if;
    return vu;
  end function;

  function to_slv(value : ufixed) return std_logic_vector
  is
    constant v : ufixed(value'length downto 1) := value;
    constant vl : std_logic_vector(value'length downto 1) := std_logic_vector(v);
  begin
    if v'length <= 0 then
      return "";
    end if;
    return vl;
  end function;

  function to_unsigned(value : ufixed) return unsigned
  is
  begin
    return unsigned(to_suv(value));
  end function;

  function to_unsigned(value : sfixed) return unsigned
  is
  begin
    return unsigned(to_suv(value));
  end function;

  function to_signed(value : sfixed) return signed
  is
  begin
    return signed(to_suv(value));
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
    elsif value >= 2.0 ** (left+1) - 2.0 ** right then
      return sat_max;
    else
      ret := ufixed(to_unsigned(integer(round(value * 2.0 ** (-right))), left - right + 1));
      return ret;
    end if;
  end function;

  function to_real(value : ufixed) return real
  is
    alias xv : ufixed(value'length-1 downto 0) is value;
  begin
    if value'length <= 0 then
      return 0.0;
    end if;

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
    ret(overlap_right-1 downto ret'right) := (others => value(overlap_right));

    return ret;
  end function;

  function resize_saturate(value : ufixed;
                           constant left, right : integer) return ufixed
  is
    variable ret : ufixed(left downto right);
  begin
    ret := resize(value, left, right);

    if value'left > left
      and value(value'left downto left+1) /= (value'left downto left+1 => '0') then
        ret := (others => '1');
    end if;

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

  function shr(a: sfixed; l : natural) return sfixed
  is
    variable ret : sfixed(a'range);
    constant w : integer := a'length - l;
  begin
    if sign(a) = '1' then
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
      report "Both ufixed arguments are not the same range, returning null vector"
        severity warning;
      return nauf;
    end if;

    ret := ufixed(unsigned(to_suv(a)) + unsigned(to_suv(b)));
    return ret;
  end function;

  function mul(a, b: ufixed;
               constant left, right : integer) return ufixed
  is
    variable au : unsigned(a'length-1 downto 0);
    variable bu : unsigned(b'length-1 downto 0);
    variable ru : unsigned(a'length+b'length-1 downto 0);
    variable rf : ufixed(a'right+b'right+ru'length-1 downto a'right+b'right);
  begin
    if a'length <= 0 or b'length <= 0 then
      return (left downto right => '0');
    end if;
    
    au := unsigned(to_suv(a));
    bu := unsigned(to_suv(b));
    ru := au * bu;
    rf := ufixed(ru);

    return resize_saturate(rf, left, right);
  end function;

  function mul(a: sfixed; b: ufixed;
               constant left, right : integer) return sfixed
  is
    constant bs : sfixed(b'left+1 downto b'right) := sfixed("0" & b);
  begin
    if a'length <= 0 or b'length <= 0 then
      return (left downto right => '0');
    end if;
    
    return mul(a, bs, left, right);
  end function;

  function mul(a, b: sfixed;
               constant left, right : integer) return sfixed
  is
    variable as : signed(a'length-1 downto 0);
    variable bs : signed(b'length-1 downto 0);
    variable rs : signed(a'length+b'length-1 downto 0);
    variable rf : sfixed(a'right+b'right+rs'length-1 downto a'right+b'right);
  begin
    if a'length <= 0 or b'length <= 0 then
      return (left downto right => '0');
    end if;
    
    as := to_signed(a);
    bs := to_signed(b);
    rs := as * bs;
    rf := sfixed(rs);
    
    return resize_saturate(rf, left, right);
  end function;

  function "-"(a, b: ufixed) return ufixed
  is
    variable ret : ufixed(a'range);
  begin
    if a'left /= b'left or a'right /= b'right then
      report "Both ufixed arguments are not the same range, returning null vector"
        severity warning;
      return nauf;
    end if;

    ret := ufixed(unsigned(to_suv(a)) - unsigned(to_suv(b)));
    return ret;
  end function;

  function sub_saturate(a, b: ufixed) return sfixed
  is
    variable ret: sfixed(a'left+1 downto a'right);
    variable xa: ufixed(a'left+1 downto a'right) := "0" & a;
    variable xb: ufixed(b'left+1 downto b'right) := "0" & b;
  begin
    ret := sfixed(xa - xb);
    return ret;
  end function;

  function to_suv(value : sfixed) return std_ulogic_vector
  is
    constant v : sfixed(value'left-value'right+1 downto 1) := value;
  begin
    if v'length <= 0 then
      return "";
    end if;
    return std_ulogic_vector(v);
  end function;

  function to_slv(value : sfixed) return std_logic_vector
  is
    constant v : sfixed(value'left-value'right+1 downto 1) := value;
  begin
    if v'length <= 0 then
      return "";
    end if;
    return std_logic_vector(v);
  end function;

  function to_sfixed(value : real;
                     constant left : integer;
                     constant right : integer) return sfixed
  is
    variable ret : sfixed(left downto right);
  begin
    if value <= -2.0**left then
      ret := (others => '0');
      ret(ret'left) := '0';
    elsif value > 2.0**left then
      ret := (others => '1');
    else
      ret := sfixed(to_signed(integer(value * 2.0 ** (-right)), left - right + 1));
    end if;
    return ret;
  end function;

  function to_real(value : sfixed) return real
  is
  begin
    if value'length <= 0 then
      return 0.0;
    end if;
    
    return real(to_integer(to_signed(value))) * 2.0 ** value'right;
  end function;

  function resize(value : sfixed;
                  constant left, right : integer) return sfixed
  is
    variable ret : sfixed(left downto right);
    constant overlap_left : integer := nsl_math.arith.min(value'left, left);
    constant overlap_right : integer := nsl_math.arith.max(value'right, right);
  begin
    ret := (others => sign(value));

    if overlap_left < overlap_right then
      return ret;
    end if;

    if value'length > 0 and ret'length > 0 then
      ret(overlap_left-1 downto overlap_right) := value(overlap_left-1 downto overlap_right);
      ret(overlap_right-1 downto ret'right) := (others => value(value'right));
    end if;

    return ret;
  end function;

  function resize_saturate(value : sfixed;
                           constant left, right : integer) return sfixed
  is
    variable ret : sfixed(left downto right);
    constant s : std_ulogic := sign(value);
  begin
    ret := resize(value, left, right);

    if left >= value'left or ret'length <= 1 then
      return ret;
    end if;

    if value'left-1 - left + 1 > 0 and value'right < left then
--      report integer'image(value'left) & ":" & integer'image(value'right)
--        & ":" & integer'image(left)  & ":" & integer'image(right)
--        severity note;
      if value(value'left-1 downto left) /= (value'left-1 downto left => s) then
        ret := (others => not s);
        ret(ret'left) := s;
      end if;
    end if;

    return ret;
  end function;

  function "+"(a, b: sfixed) return sfixed
  is
    variable ret : sfixed(a'range);
  begin
    if a'left /= b'left or a'right /= b'right then
      report "Both arguments are not the same range, returning null vector"
        severity warning;
      return nasf;
    end if;

    ret := sfixed(signed(to_suv(a)) + signed(to_suv(b)));
    return ret;
  end function;

  function add_extend(a, b: sfixed) return sfixed
  is
    variable xa: sfixed(a'left+1 downto a'right) := sign(a) & a;
    variable xb: sfixed(b'left+1 downto b'right) := sign(b) & b;
  begin
    return xa + xb;
  end function;

  function add_saturate(a, b: sfixed) return sfixed
  is
  begin
    return resize_saturate(add_extend(a, b), a'left, a'right);
  end function;

  function "-"(a, b: sfixed) return sfixed
  is
    variable ret : sfixed(a'range);
  begin
    if a'left /= b'left or a'right /= b'right then
      report "Both ufixed arguments are not the same range, returning null vector"
        severity warning;
      return nasf;
    end if;

    ret := sfixed(to_signed(a) - to_signed(b));
    return ret;
  end function;

  function sub_extend(a, b: sfixed) return sfixed
  is
    variable xa: sfixed(a'left+1 downto a'right) := sign(a) & a;
    variable xb: sfixed(b'left+1 downto b'right) := sign(b) & b;
  begin
    return xa - xb;
  end function;

  function "abs"(a: sfixed) return ufixed
  is
    variable ret : sfixed(a'left+1 downto a'right);
  begin
    if sign(a) = '1' then
      ret := -a;
    else
      ret := "0" & a;
    end if;
    return ufixed(ret);
  end function;

  function "-"(a: ufixed) return ufixed
  is
    variable ret, lsb : ufixed(a'range);
  begin
    lsb := (others => '0');
    lsb(a'right) := '1';
    ret := (not a) + lsb;
    return ret;
  end function;

  function "-"(a: sfixed) return sfixed
  is
    variable ret, lsb : sfixed(a'range);
  begin
    lsb := (others => '0');
    lsb(a'right) := '1';
    ret := (not a) + lsb;
    return ret;
  end function;

  function neg_extend(a: sfixed) return sfixed
  is
    variable aa, ret, lsb : sfixed(a'left+1 downto a'right);
  begin
    aa := sign(a) & a;
    lsb := (others => '0');
    lsb(lsb'right) := '1';
    ret := (not aa) + lsb;
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
      report "Both sfixed arguments are not the same range, cannot compare"
        severity warning;
      return false;
    end if;

    return signed(to_suv(a)) <= signed(to_suv(b));
  end function;

  function to_string(value: ufixed) return string
  is
    constant int : string := to_string(to_suv(value(value'left downto 0)));
    constant frac : string := to_string(to_suv(value(-1 downto value'right)));
  begin
    return int & "." & frac;
  end function;

  function to_string(value: sfixed) return string
  is
    constant int : string := to_string(to_suv(value(value'left downto 0)));
    constant frac : string := to_string(to_suv(value(-1 downto value'right)));
  begin
    return int & "." & frac;
  end function;

  function to_ufixed_saturate(s: sfixed;
                              constant left, right : integer) return ufixed
  is
    variable ret: ufixed(left downto right);
    constant su: ufixed(s'left-1 downto s'right) := ufixed(s(s'left-1 downto s'right));
  begin
    if sign(s) = '1' then
      ret := (others => '0');
    else
      ret := resize_saturate(su, left, right);
    end if;
    
    return ret;
  end function;

  function to_sfixed(u: ufixed) return sfixed
  is
    constant ret: sfixed(u'left+1 downto u'right) := "0" & sfixed(u);
  begin
    return ret;
  end function;

  function to_sfixed_scaled(u: ufixed) return sfixed
  is
    constant ret: sfixed(u'left downto u'right) := (not u(u'left)) & sfixed(u(u'left-1 downto u'right));
  begin
    return ret;
  end function;

  function to_ufixed_scaled(s: sfixed) return ufixed
  is
    constant ret: ufixed(s'left downto s'right) := (not sign(s)) & ufixed(s(s'left-1 downto s'right));
  begin
    return ret;
  end function;

  function "="(a: sfixed; b: real) return boolean
  is
    constant bf: sfixed(a'range) := to_sfixed(b, a'left, a'right);
  begin
    return a = bf;
  end function;

  function "/="(a: sfixed; b: real) return boolean
  is
    constant bf: sfixed(a'range) := to_sfixed(b, a'left, a'right);
  begin
    return a /= bf;
  end function;

  function ">"(a: sfixed; b: real) return boolean
  is
    constant bf: sfixed(a'range) := to_sfixed(b, a'left, a'right);
  begin
    return a > bf;
  end function;

  function "<"(a: sfixed; b: real) return boolean
  is
    constant bf: sfixed(a'range) := to_sfixed(b, a'left, a'right);
  begin
    return a < bf;
  end function;

  function ">="(a: sfixed; b: real) return boolean
  is
    constant bf: sfixed(a'range) := to_sfixed(b, a'left, a'right);
  begin
    return a >= bf;
  end function;

  function "<="(a: sfixed; b: real) return boolean
  is
    constant bf: sfixed(a'range) := to_sfixed(b, a'left, a'right);
  begin
    return a <= bf;
  end function;

  function "="(a: ufixed; b: real) return boolean
  is
    constant bf: ufixed(a'range) := to_ufixed(b, a'left, a'right);
  begin
    return a = bf;
  end function;

  function "/="(a: ufixed; b: real) return boolean
  is
    constant bf: ufixed(a'range) := to_ufixed(b, a'left, a'right);
  begin
    return a /= bf;
  end function;

  function ">"(a: ufixed; b: real) return boolean
  is
    constant bf: ufixed(a'range) := to_ufixed(b, a'left, a'right);
  begin
    return a > bf;
  end function;

  function "<"(a: ufixed; b: real) return boolean
  is
    constant bf: ufixed(a'range) := to_ufixed(b, a'left, a'right);
  begin
    return a < bf;
  end function;

  function ">="(a: ufixed; b: real) return boolean
  is
    constant bf: ufixed(a'range) := to_ufixed(b, a'left, a'right);
  begin
    return a >= bf;
  end function;

  function "<="(a: ufixed; b: real) return boolean
  is
    constant bf: ufixed(a'range) := to_ufixed(b, a'left, a'right);
  begin
    return a <= bf;
  end function;

end package body;
