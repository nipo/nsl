library ieee;
use ieee.std_logic_1164.all;

package logging is

  component synth_log is
    generic(
      message_c: string
      );
    port(
      unused_i : in std_ulogic
      );
  end component;
  
end package;
