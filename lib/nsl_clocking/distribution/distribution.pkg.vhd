library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package distribution is

  component clock_buffer is
    generic(
      -- Buffer mode.
      -- Typical values are "global", "region", "row", "io", "none". Others may exist.
      -- "none" is always implemented. Other modes are
      -- implementation-specific and may fallback to "global".
      mode_c : string := "global"
      );
    port(
      clock_i      : in std_ulogic;
      clock_o      : out std_ulogic
      );
  end component;

end package distribution;