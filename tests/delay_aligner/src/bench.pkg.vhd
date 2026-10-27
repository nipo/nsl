library ieee;
use ieee.std_logic_1164.all;

package bench is

  constant tap_count_max_c : integer := 64;
  constant slip_count_c : integer := 10;

  -- Tap index for "any tap is acceptable".
  constant any_c : integer := -1;

  type scenario_t is
  record
    -- Valid taps, at slip position "slip" only.
    eye: std_ulogic_vector(0 to tap_count_max_c-1);
    slip: integer range 0 to slip_count_c-1;
    tap: integer;
  end record;

  type scenario_vector is array(natural range <>) of scenario_t;

  function eye(tap_count: integer; first, last: integer) return std_ulogic_vector;

end package;

package body bench is

  function eye(tap_count: integer; first, last: integer) return std_ulogic_vector is
    variable ret: std_ulogic_vector(0 to tap_count_max_c-1) := (others => '0');
    variable t: integer := first;
  begin
    loop
      ret(t mod tap_count) := '1';
      exit when t mod tap_count = last mod tap_count;
      t := t + 1;
    end loop;
    return ret;
  end function;

end package body;
