library ieee;
use ieee.std_logic_1164.all;

library nsl_math;

package probability is

  component probability_stream is
    generic (
      state_width_c: integer range 1 to 31 := 8
      );
    port (
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      probability_i : in nsl_math.fixed.ufixed(-1 downto -state_width_c);

      ready_i : in std_ulogic := '1';
      value_o : out std_ulogic
      );
  end component;

  component probability_stream_constant is
    generic (
      state_width_c: integer range 1 to 31 := 8;
      probability_c: real
      );
    port (
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      ready_i : in std_ulogic := '1';
      value_o : out std_ulogic
      );
  end component;
  
end package probability;
