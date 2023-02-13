library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math, work;
use work.timestamp.all;
use nsl_math.fixed.all;

package clock is
  
  component clock_adjustable is
    port(
      clock_i : in  std_ulogic;
      reset_n_i : in std_ulogic;

      sub_nanosecond_inc_i: in ufixed;

      nanosecond_adj_i: in timestamp_nanosecond_offset_t := (others => '0');
      nanosecond_adj_set_i: in std_ulogic := '0';

      timestamp_i: in timestamp_t;
      timestamp_set_i: in std_ulogic := '0';

      timestamp_o: out timestamp_t
      );
  end component;

end package clock;
