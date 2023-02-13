library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.timestamp.all;

package pps is

  -- This component generates a tick every time we cross a second boundary.
  --
  -- Reference timestamp is allowed to jump of less than a second
  -- backwards.  Even if a given second boundary is crossed twice,
  -- tick will be asserted only once.
  --
  -- All second values must be present at least one cycle in order for this to
  -- work properly. Second non-monotomic behavior is permitted when
  -- reference.abs_change is asserted.
  component pps_ticker is
    port(
      clock_i : in  std_ulogic;
      reset_n_i : in std_ulogic;

      reference_i: in timestamp_t;

      tick_o: out std_ulogic
      );
  end component;
  
end package pps;
