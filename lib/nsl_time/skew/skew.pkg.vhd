library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.timestamp.all;

package skew is

  -- This measures skew between two clocks.
  -- Clocks are sampled on every cycle and their respective skew is given after
  -- some latency on output port.
  --
  -- Output offset saturates to +/-999999999 ns.
  component skew_measurer is
    port(
      clock_i : in  std_ulogic;
      reset_n_i : in std_ulogic;

      -- This input is not relevant for calculation. It allows to assert for
      -- pipeline latency of measurement. Its value is propagated on output
      -- side when matching samples are measured.
      strobe_i : in std_ulogic := '0';
      -- Whatever the strobe_i value, every clock cycle triggers a measurement
      -- of the offset.
      reference_i: in timestamp_t;
      skewed_i: in timestamp_t;

      strobe_o : out std_ulogic;
      offset_o: out timestamp_nanosecond_offset_t
      );
  end component;

  -- This applies skew to a timestamp. Offset is sampled at the same
  -- time as reference clock. This module outputs clock with applied
  -- offset after some fixed latency.
  --
  -- This module does not compensate for its own latency.
  --
  -- Offsets are assumed to be small, in case there is an absolute
  -- change in reference timestamp, abs_change should be asserted and
  -- will be propagated.
  component skew_offsetter is
    port(
      clock_i : in  std_ulogic;
      reset_n_i : in std_ulogic;

      reference_i: in timestamp_t;
      offset_i: in timestamp_nanosecond_offset_t;

      skewed_o: out timestamp_t
      );
  end component;
  
end package skew;
