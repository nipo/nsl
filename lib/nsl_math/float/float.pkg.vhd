library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math;
use nsl_math.fixed.all;

package float is

  type float32 is
  record
    sign : std_ulogic;
    exp : unsigned(7 downto 0);
    mantissa : ufixed(-1 downto -23);
  end record;

  type float64 is
  record
    sign : std_ulogic;
    exp : unsigned(10 downto 0);
    mantissa : ufixed(-1 downto -52);
  end record;
  
  function to_float32(value: ufixed; sign: std_ulogic := '0') return float32;
  function to_float32(value: sfixed) return float32;
--  function to_float32(value: real) return float32;
  function to_float64(value: ufixed; sign: std_ulogic := '0') return float64;
  function to_float64(value: sfixed) return float64;
--  function to_float64(value: real) return float64;

  function to_suv(f: float32) return std_ulogic_vector;
  function to_suv(f: float64) return std_ulogic_vector;
  
end package float;

package body float is

  function to_float32(value: ufixed; sign: std_ulogic := '0') return float32
  is
    variable f : float32;
    constant eb : integer := (2 ** (f.exp'length-1)) - 1;
    variable bit_count : integer;
  begin
    f.sign := sign;
    f.mantissa := (others => '0');
    f.exp := (others => '0');

    bit_count := 0;
    find_msb: for msb in value'left downto value'right
    loop
      if value(msb) = '1' then
        bit_count := nsl_math.arith.min(msb - value'right, f.mantissa'length);

        f.exp := to_unsigned(msb + eb, f.exp'length);
        f.mantissa(f.mantissa'left downto f.mantissa'left - bit_count + 1)
          := ufixed(value(msb - 1 downto msb - bit_count));

        return f;
      end if;
    end loop;

    return f;
  end function;
    
  function to_float32(value: sfixed) return float32
  is
    variable tmp : ufixed(value'left downto value'right);
  begin
    if value(value'left) = '0' then
      return to_float32(ufixed(value));
    else
      tmp := ufixed(-value);
      return to_float32(tmp, '1');
    end if;
  end function;

  function to_float64(value: ufixed; sign: std_ulogic := '0') return float64
  is
    variable f : float64;
    constant eb : integer := (2 ** (f.exp'length-1)) - 1;
    variable bit_count : integer;
  begin
    f.sign := sign;
    f.mantissa := (others => '0');
    f.exp := (others => '0');

    bit_count := 0;
    find_msb: for msb in value'left downto value'right
    loop
      if value(msb) = '1' then
        bit_count := nsl_math.arith.min(msb - value'right, f.mantissa'length);

        f.exp := to_unsigned(msb + eb, f.exp'length);
        f.mantissa(f.mantissa'left downto f.mantissa'left - bit_count + 1)
          := ufixed(value(msb - 1 downto msb - bit_count));

        return f;
      end if;
    end loop;

    return f;
  end function;
    
  function to_float64(value: sfixed) return float64
  is
    variable tmp : ufixed(value'left downto value'right);
  begin
    if value(value'left) = '0' then
      return to_float64(ufixed(value));
    else
      tmp := ufixed(-value);
      return to_float64(tmp, '1');
    end if;
  end function;

  function to_suv(f: float32) return std_ulogic_vector
  is
    variable ret: std_ulogic_vector(31 downto 0);
  begin
    ret(ret'left) := f.sign;
    ret(ret'left-1 downto f.mantissa'length) := std_ulogic_vector(f.exp);
    ret(f.mantissa'length-1 downto 0) := to_suv(f.mantissa);

    return ret;
  end function;

  function to_suv(f: float64) return std_ulogic_vector
  is
    variable ret: std_ulogic_vector(63 downto 0);
  begin
    ret(ret'left) := f.sign;
    ret(ret'left-1 downto f.mantissa'length) := std_ulogic_vector(f.exp);
    ret(f.mantissa'length-1 downto 0) := to_suv(f.mantissa);

    return ret;
  end function;

end package body float;
