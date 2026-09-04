library ieee;
use ieee.std_logic_1164.all;

package assertion is

  -- Hacky procedure for failing elaboration if condition is not true.
  procedure synth_assert(constant condition_c : in boolean);
  
  function resolve(c: boolean) return integer;
  
end package;

package body assertion is

  function resolve(c: boolean) return integer
  is
  begin
    if c then
      return 0;
    else
      return 1;
    end if;
  end function;  

  procedure synth_assert(constant condition_c : in boolean)
  is
    variable assert_fail: std_ulogic_vector(0 to 0);
  begin
    assert_fail(resolve(condition_c)) := '-';
  end procedure;

end package body;
