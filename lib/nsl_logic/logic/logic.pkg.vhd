library ieee;
use ieee.std_logic_1164.all;

package logic is

  function popcnt(v : std_ulogic_vector) return integer;
  function xor_reduce(x : std_ulogic_vector) return std_ulogic;
  function and_reduce(x : std_ulogic_vector) return std_ulogic;
  function or_reduce(x : std_ulogic_vector) return std_ulogic;
  function mask_merge(for0, for1, sel : std_ulogic_vector) return std_ulogic_vector;
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
    variable ret: std_ulogic_vector(sel'range);
  begin
    assert for0'length = for1'length
      report "Input vectors must have the same length"
      severity failure;
    assert for0'length = sel'length
      report "Input vectors and selector must have the same length"
      severity failure;

    ret := (for0 and not sel) or (for1 and sel);

    return ret;
  end mask_merge;

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

end package body logic;
