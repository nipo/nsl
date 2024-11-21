library ieee;
use ieee.std_logic_1164.all;

package diff is

  type diff_pair is record
    p : std_ulogic;
    n : std_ulogic;
  end record;

  type diff_pair_vector is array(natural range <>) of diff_pair;

  function to_diff(v: std_ulogic) return diff_pair;
  function to_se(d: diff_pair) return std_ulogic;
  function swap(d: diff_pair; swap: boolean := true) return diff_pair;

  -- Swap pairs depending on a mask. Mask and diff pair vector should be of the
  -- same length.
  function swap(d: diff_pair_vector; swap_mask: std_ulogic_vector) return diff_pair_vector;

  function bitswap(d: diff_pair_vector) return diff_pair_vector;

  -- Takes a vector of wires and map them to half the number of diff pairs.
  -- Input vector direction is unimportant.
  -- First P appears on the left, last N appears on the right. Vector contents
  -- is P/N two by two.
  -- Returns a vector where pairs are in the same order as input vector.
  -- Optionally, pairs may be swapped. Swap mask is taken from the left. It
  -- shorter, no swap is assumed.
  function from_pnpn(v: std_ulogic_vector;
                     swap_mask: std_ulogic_vector := "0") return diff_pair_vector;

  -- Takes a vector of wires and map them to half the number of diff pairs.
  -- Input vector direction is unimportant.
  -- All P appear on the left, all N appear on the right.
  -- Returns a vector where pairs are in the same order as input vector.
  -- Optionally, pairs may be swapped. Swap mask is taken from the left. It
  -- shorter, no swap is assumed.
  function from_ppnn(v: std_ulogic_vector;
                     swap_mask: std_ulogic_vector := "0") return diff_pair_vector;

  -- Takes a vector of diff pairs and map them to twice the number of wires.
  -- Input vector direction is unimportant.
  -- Maps output in the same order, with P on the left, N on the right.
  -- Optionally, pairs may be swapped. Swap mask is taken in same order as the
  -- vector, if shorter, no swap is assumed.
  function to_pnpn(v: diff_pair_vector;
                   swap_mask: std_ulogic_vector := "0") return std_ulogic_vector;

  -- Takes a vector of diff pairs and map them to twice the number of
  -- wires.  Input vector direction is unimportant.  Maps output in
  -- the same order, with all Ps in order on the left, all Ns on the
  -- right.  Optionally, pairs may be swapped. Swap mask is taken in
  -- same order as the vector, if shorter, no swap is assumed.
  function to_ppnn(v: diff_pair_vector;
                   swap_mask: std_ulogic_vector := "0") return std_ulogic_vector;

end package diff;

package body diff is

  function to_diff(v: std_ulogic) return diff_pair
  is
    variable ret : diff_pair;
  begin
    ret.p := v;
    ret.n := not v;
    return ret;
  end function;

  function to_se(d: diff_pair) return std_ulogic
  is
  begin
    if to_x01(d.p) = not to_x01(d.n) then
      return to_x01(d.p);
    else
      return 'X';
    end if;
  end function;

  function swap(d: diff_pair; swap: boolean := true) return diff_pair
  is
  begin
    if swap then
      return (p => d.n, n => d.p);
    else
      return d;
    end if;
  end function;

  function swap(d: diff_pair_vector; swap_mask: std_ulogic_vector) return diff_pair_vector
  is
    alias dd: diff_pair_vector(d'length-1 downto 0) is d;
    alias md: std_ulogic_vector(d'length-1 downto 0) is swap_mask;
    variable ret : diff_pair_vector(d'length-1 downto 0);
  begin
    for i in dd'range
    loop
      ret(i) := swap(dd(i), md(i) = '1');
    end loop;
    return ret;
  end function;

  function bitswap(d: diff_pair_vector) return diff_pair_vector
  is
    alias dd: diff_pair_vector(d'length-1 downto 0) is d;
    variable ret : diff_pair_vector(d'length-1 downto 0);
  begin
    for i in dd'range
    loop
      ret(dd'length-1-i) := dd(i);
    end loop;
    return ret;
  end function;

  function vector_extend(v: std_ulogic_vector;
                         s: integer) return std_ulogic_vector
  is
    alias vd: std_ulogic_vector(0 to v'length-1) is v;
    constant z: std_ulogic_vector(0 to s-1) := (others => '0');
  begin
    if vd'length >= s then
      return vd(0 to s-1);
    end if;
    
    return vd & z(vd'length to s-1);
  end function;
  
  function from_pnpn(v: std_ulogic_vector;
                     swap_mask: std_ulogic_vector := "0") return diff_pair_vector
  is
    alias vd: std_ulogic_vector(0 to v'length-1) is v;
    variable ret: diff_pair_vector(0 to v'length/2-1);
    variable inv: std_ulogic_vector(0 to v'length/2-1) := vector_extend(swap_mask, ret'length);
  begin
    for i in ret'range
    loop
      if inv(i) = '1' then
        ret(i) := (p => vd(i*2 + 1), n => vd(i*2));
      else
        ret(i) := (p => vd(i*2), n => vd(i*2 + 1));
      end if;
    end loop;

    return ret;
  end function;
  
  function from_ppnn(v: std_ulogic_vector;
                     swap_mask: std_ulogic_vector := "0") return diff_pair_vector
  is
    alias vd: std_ulogic_vector(0 to v'length-1) is v;
    variable ret : diff_pair_vector(0 to v'length/2-1);
    variable inv: std_ulogic_vector(0 to v'length/2-1) := vector_extend(swap_mask, ret'length);
  begin
    for i in ret'range
    loop
      if inv(i) = '1' then
        ret(i) := (p => vd(i + ret'length), n => vd(i));
      else
        ret(i) := (p => vd(i), n => vd(i + ret'length));
      end if;
    end loop;

    return ret;
  end function;
  
  function to_pnpn(v: diff_pair_vector;
                   swap_mask: std_ulogic_vector := "0") return std_ulogic_vector
  is
    alias vd: diff_pair_vector(0 to v'length-1) is v;
    variable ret : std_ulogic_vector(0 to v'length*2-1);
    variable inv: std_ulogic_vector(0 to v'length-1) := vector_extend(swap_mask, v'length);
  begin
    for i in vd'range
    loop
      if inv(i) = '1' then
        ret(i*2 + 0) := vd(i).p;
        ret(i*2 + 1) := vd(i).n;
      else
        ret(i*2 + 0) := vd(i).n;
        ret(i*2 + 1) := vd(i).p;
      end if;
    end loop;

    return ret;
  end function;

  function to_ppnn(v: diff_pair_vector;
                   swap_mask: std_ulogic_vector := "0") return std_ulogic_vector
  is
    alias vd: diff_pair_vector(0 to v'length-1) is v;
    variable ret : std_ulogic_vector(0 to v'length*2-1);
    variable inv: std_ulogic_vector(0 to v'length-1) := vector_extend(swap_mask, v'length);
  begin
    for i in vd'range
    loop
      if inv(i) = '1' then
        ret(i) := vd(i).p;
        ret(i + vd'length) := vd(i).n;
      else
        ret(i) := vd(i).n;
        ret(i + vd'length) := vd(i).p;
      end if;
    end loop;

    return ret;
  end function;

end package body diff;
