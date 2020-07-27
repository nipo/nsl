library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package frequency is

  -- Generates a periodic signal with given frequency, in Hz
  component frequency_generator
    generic (
      -- clock_i frequency (hz)
      clock_rate_c : positive
      );
    port (
      reset_n_i   : in  std_ulogic;
      clock_i     : in  std_ulogic;

      frequency_i : in unsigned;

      value_o : out std_ulogic
      );
  end component;

end package frequency;
