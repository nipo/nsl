library ieee;
use ieee.std_logic_1164.all;

package assertion is

  -- Hacky component for failing elaboration if condition is not true.
  --
  -- Apart from this, this component has no use.
  component synth_assert is
    generic(
      message_c: string;
      condition_c: boolean
      );
    port(
      unused_i : in std_ulogic
      );
  end component;
  
end package;
