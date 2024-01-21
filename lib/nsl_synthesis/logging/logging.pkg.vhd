library ieee;
use ieee.std_logic_1164.all;

package logging is

  -- Hacky component for spilling logs during synthesis for stupid
  -- tools that do not handle asserts at all.
  --
  -- Vendors usually spill generic parameters of elaborated modules to
  -- the log, put message in generics.
  --
  -- Apart from this, this component has no use.
  component synth_log is
    generic(
      message_c: string
      );
    port(
      unused_i : in std_ulogic
      );
  end component;
  
end package;
