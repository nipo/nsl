library ieee;
use ieee.std_logic_1164.all;

library nsl_synthesis;
use nsl_synthesis.assertion.all;

entity tb is
  generic(
    in_function : boolean := false;
    in_line : boolean := true
  );
end tb;

architecture arch of tb is

begin

  test_function : if in_function generate
    function inside_function(c : boolean) return boolean
    is
      variable ret_val : boolean;    
    begin
      synth_assert(c);
      return false; -- Never reach this statement
    end function;

    constant ret_val : boolean := inside_function(2 + 2 = 5);

  begin
  end generate;  

  test_in_line : if in_line generate
  begin
    -- Test failing inline
    synth_assert(2 + 2 = 5);
  end generate;

end architecture;
