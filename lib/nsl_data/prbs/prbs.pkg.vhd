library ieee, nsl_data, nsl_logic;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use nsl_data.bytestream.all;
use nsl_logic.logic.xor_reduce;

-- Generic PRBS implementation
package prbs is

  -- A PRBS state
  type prbs_state is array(natural range <>) of std_ulogic;

  function "not"(x:prbs_state) return prbs_state;
  function "xor"(x, y:prbs_state) return prbs_state;
  function "="(x, y:prbs_state) return boolean;
  function "/="(x, y:prbs_state) return boolean;
  function bitswap(x:prbs_state) return prbs_state;

  -- Moves `count` cycles forward in the PRBS stream, yields next
  -- state.
  function prbs_forward(state, poly : prbs_state;
                         count : integer := 1) return prbs_state;
  -- Moves `count` cycles backwards in the PRBS stream, yields next
  -- state.
  function prbs_backward(state, poly : prbs_state;
                         count : integer := 1) return prbs_state;
  -- Generates a PRBS byte string from initial value and generating
  -- polynom
  function prbs_byte_string(init, poly : prbs_state;
                            length : integer) return byte_string;

  -- Generates subsequent bytes for a given PRBS and state. Updates
  -- state.
  procedure prbs_next(constant poly : in prbs_state;
                      variable state : inout prbs_state;
                      variable data : out byte_string);

  -- Known PRBS polynoms
  constant prbs7 : prbs_state(7 downto 0) := (7 => '1', 6 => '1', 0 => '1', others => '0');
  constant prbs9 : prbs_state(9 downto 0) := (9 => '1', 5 => '1', 0 => '1', others => '0');
  constant prbs11 : prbs_state(11 downto 0) := (11 => '1', 9 => '1', 0 => '1', others => '0');
  constant prbs15 : prbs_state(15 downto 0) := (15 => '1', 14 => '1', 0 => '1', others => '0');
  constant prbs20 : prbs_state(20 downto 0) := (20 => '1', 3 => '1', 0 => '1', others => '0');
  constant prbs23 : prbs_state(23 downto 0) := (23 => '1', 18 => '1', 0 => '1', others => '0');
  constant prbs31 : prbs_state(31 downto 0) := (31 => '1', 28 => '1', 0 => '1', others => '0');
  
end package prbs;

package body prbs is

  function "not"(x:prbs_state) return prbs_state is
    variable ret : prbs_state(x'range) := x;
  begin
    for i in ret'range
    loop
      ret(i) := not ret(i);
    end loop;
    return ret;
  end function;

  function "xor"(x, y:prbs_state) return prbs_state
  is
  begin
    return prbs_state(std_ulogic_vector(x) xor std_ulogic_vector(y));
  end function;

  function "="(x, y:prbs_state) return boolean is
  begin
    return std_ulogic_vector(x) = std_ulogic_vector(y);
  end function;

  function "/="(x, y:prbs_state) return boolean is
  begin
    return std_ulogic_vector(x) = std_ulogic_vector(y);
  end function;

  function bitswap(x:prbs_state) return prbs_state is
    alias xx: prbs_state(0 to x'length - 1) is x;
    variable rx: prbs_state(x'length - 1 downto 0);
  begin
    for i in xx'range
    loop
      rx(i) := xx(i);
    end loop;
    return rx;
  end function;

  function prbs_forward(state, poly : prbs_state;
                         count : integer := 1) return prbs_state is
    alias xstate : prbs_state(state'length-1 downto 0) is state;
    alias xpoly : prbs_state(poly'length-1 downto 0) is poly;
    variable tmp : prbs_state(state'length-1 downto 0);
  begin
    assert state'length = poly'length - 1
      report "State must be 1 bit less than polynom"
      severity failure;
    assert poly(poly'left) = '1' and poly(poly'right) = '1'
      report "Polynom must begin and end with '1'"
      severity failure;

    tmp := xstate;
    for i in 1 to count
    loop
      tmp := tmp(tmp'left-1 downto 0)
                & xor_reduce(std_ulogic_vector(tmp) and std_ulogic_vector(poly(poly'left downto 1)));
    end loop;

    return tmp;
  end function;

  function prbs_backward(state, poly : prbs_state;
                         count : integer := 1) return prbs_state is
    alias xstate : prbs_state(state'length-1 downto 0) is state;
    alias xpoly : prbs_state(poly'length-1 downto 0) is poly;
    variable tmp : prbs_state(state'length-1 downto 0);
  begin
    assert state'length = poly'length - 1
      report "State must be 1 bit less than polynom"
      severity failure;
    assert poly(poly'left) = '1' and poly(poly'right) = '1'
      report "Polynom must begin and end with '1'"
      severity failure;

    tmp := xstate;
    for i in 1 to count
    loop
      tmp := xor_reduce(std_ulogic_vector(tmp) and std_ulogic_vector(poly(poly'left-1 downto 0))) & tmp(tmp'left downto 1);
    end loop;

    return tmp;
  end function;

  function prbs_byte_string(init, poly : prbs_state;
                            length : integer) return byte_string
  is
    alias xinit : prbs_state(init'length-1 downto 0) is init;
    variable ret : byte_string(0 to length-1);
    variable tmp : prbs_state(init'length-1 downto 0);
  begin
    assert init'length >= 8
      report "Cannot do bytes with less than 8-bit state"
      severity failure;

    tmp := init;

    for i in ret'range
    loop
      for j in 0 to 7
      loop
        ret(i)(j) := tmp(tmp'left);
        tmp := prbs_forward(tmp, poly, 1);
      end loop;
    end loop;

    return ret;
  end function;

  procedure prbs_next(constant poly : in prbs_state;
                      variable state : inout prbs_state;
                      variable data : out byte_string)
  is
    variable ret : byte_string(0 to data'length-1);
    variable tmp : prbs_state(state'length-1 downto 0);
  begin
    assert state'length >= 8
      report "Cannot do bytes with less than 8-bit state"
      severity failure;

    tmp := state;

    for i in ret'range
    loop
      for j in 0 to 7
      loop
        ret(i)(j) := tmp(tmp'left);
        tmp := prbs_forward(tmp, poly, 1);
      end loop;
    end loop;

    state := tmp;
    data := ret;
  end procedure;

end package body prbs;
