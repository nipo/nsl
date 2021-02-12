library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package uid is

  -- Abstraction of actual device UID. Normalizes output as a 32-bit
  -- number. Conversion algorithm from device internal UID to 32 bits
  -- is undefined.
  component uid32_reader
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      done_o : out std_ulogic;
      uid_o : out unsigned(31 downto 0)
      );
  end component;

end package uid;
