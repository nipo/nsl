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

  -- This component recovers a clock from a 1-PPS tick.
  component clock_from_pps is
    generic(
      clock_nominal_hz_c: natural;
      clock_max_abs_ppm_c: real := 5.0
      );
    port(
      clock_i : in  std_ulogic;
      reset_n_i : in std_ulogic;

      -- Second setter. It sets the second field of the timestamp. When
      -- set, timestamp absolute jump is asserted.  This is updated in
      -- timestamp on next PPS. This should be set at least 10 cycles
      -- before pps is asserted.
      next_second_i: in timestamp_second_t;
      next_second_set_i: in std_ulogic;

      -- PPS edge, this is the time where timestamp should cross a
      -- second boundary.
      tick_i: in std_ulogic;

      timestamp_o : out timestamp_t
      );
  end component;
  
end package clock;
