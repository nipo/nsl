library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package logic is

  function popcnt(v : std_ulogic_vector) return integer;
  function xor_reduce(x : std_ulogic_vector) return std_ulogic;
  function and_reduce(x : std_ulogic_vector) return std_ulogic;
  function or_reduce(x : std_ulogic_vector) return std_ulogic;
  function all_set(x : std_ulogic_vector) return boolean;
  function any_set(x : std_ulogic_vector) return boolean;
  function mask_merge(for0, for1, sel : std_ulogic_vector) return std_ulogic_vector;
  function mask_merge(for0, for1: unsigned; sel : std_ulogic_vector) return unsigned;
  function mask_merge(for0, for1, sel: unsigned) return unsigned;
  function mask_range(width, lsb, msb : natural;
                      range_bit: std_ulogic := '1') return std_ulogic_vector;

end package logic;

package body logic is

  function popcnt(v : std_ulogic_vector) return integer
  is
    variable r : integer;
  begin
    r := 0;

    for i in v'range
    loop
      if to_x01(v(i)) = '1' then
        r := r + 1;
      end if;
    end loop;

    return r;
  end function;
    
  function xor_reduce(x : std_ulogic_vector) return std_ulogic is
    variable ret : std_ulogic;
  begin
    ret := '0';

    for i in x'range
    loop
      ret := ret xor x(i);
    end loop;

    return ret;
  end xor_reduce;

  function and_reduce(x : std_ulogic_vector) return std_ulogic is
    variable ret : std_ulogic;
  begin
    ret := '1';

    for i in x'range
    loop
      ret := ret and x(i);
    end loop;

    return ret;
  end and_reduce;

  function or_reduce(x : std_ulogic_vector) return std_ulogic is
    variable ret : std_ulogic;
  begin
    ret := '0';

    for i in x'range
    loop
      ret := ret or x(i);
    end loop;

    return ret;
  end or_reduce;

  function mask_merge(for0, for1, sel : std_ulogic_vector) return std_ulogic_vector is
    alias f0: std_ulogic_vector(0 to for0'length-1) is for0;
    alias f1: std_ulogic_vector(0 to for1'length-1) is for1;
    alias s: std_ulogic_vector(0 to sel'length-1) is sel;
    variable ret: std_ulogic_vector(s'range);
  begin
    assert for0'length = for1'length
      report "Input vectors must have the same length"
      severity failure;
    assert for0'length = sel'length
      report "Input vectors and selector must have the same length"
      severity failure;

    for i in ret'range
    loop
      case s(i) is
        when '1' | 'H' =>
          ret(i) := f1(i);
        when '0' | 'L' =>
          ret(i) := f0(i);
        when '-' =>
          ret(i) := '-';
        when others =>
          ret(i) := 'X';
      end case;
    end loop;

    return ret;
  end mask_merge;

  function mask_merge(for0, for1: unsigned; sel : std_ulogic_vector) return unsigned
  is
  begin
    return unsigned(mask_merge(std_ulogic_vector(for0), std_ulogic_vector(for1), sel));
  end function;
    
  function mask_merge(for0, for1, sel: unsigned) return unsigned
  is
  begin
    return unsigned(mask_merge(for0, for1, std_ulogic_vector(sel)));
  end function;

  function mask_range(width, lsb, msb : natural;
                      range_bit: std_ulogic := '1') return std_ulogic_vector is
    variable ret: std_ulogic_vector(width - 1 downto 0);
  begin
    assert lsb < width
      report "Invalid lsb index"
      severity failure;
    assert msb < width
      report "Invalid msb index"
      severity failure;
    assert lsb <= msb
      report "range in bad order"
      severity failure;

    for i in ret'range
    loop
      if lsb <= i and i <= msb then
        ret(i) := range_bit;
      else
        ret(i) := not range_bit;
      end if;
    end loop;

    return ret;
  end function;

  function all_set(x : std_ulogic_vector) return boolean
  is
  begin
    return and_reduce(x) = '1';
  end function;

  function any_set(x : std_ulogic_vector) return boolean
  is
  begin
    return or_reduce(x) = '1';
  end function;

end package body logic;
