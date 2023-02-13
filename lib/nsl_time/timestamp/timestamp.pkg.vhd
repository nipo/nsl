library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- This package handles timestamps suitable for precise clock synchronization,
-- either through PTP or through a PPS input.
package timestamp is
  
  subtype timestamp_second_t is unsigned(31 downto 0);
  subtype timestamp_nanosecond_t is unsigned(29 downto 0);
  subtype timestamp_nanosecond_offset_t is signed(30 downto 0);

  -- Reference timescale is undefined
  type timestamp_t is
  record
    -- If asserted, this means seconds may jump in any direction in a
    -- non-monotonic way.
    abs_change: std_ulogic;
    second : timestamp_second_t;
    nanosecond : timestamp_nanosecond_t;
  end record;

  constant timestamp_zero_c: timestamp_t := (
    abs_change => '0',
    second => (others => '0'),
    nanosecond => (others => '0')
    );

  -- Convert from flat std_logic / std_logic_vectors values that may
  -- appear on inexpressive module interfaces
  function from_sl(
    second: in std_logic_vector;
    nanosecond: in std_logic_vector;
    abs_change: in std_logic) return timestamp_t;

  -- Convert back to std_logic and std_logic_vector.
  function second_slv(ts: timestamp_t) return std_logic_vector;
  function nanosecond_slv(ts: timestamp_t) return std_logic_vector;
  function abs_change_sl(ts: timestamp_t) return std_logic;

  -- See IEEE-1588-2019 Annex B for references
  -- NTP = PTP + 2208988800 s - utc_offset
  -- constant ptp_to_ntp_base_offset_c : integer := 2_208_988_800; -- Too big to represent in integer

  -- PTP = GPS + 315964819 s
  constant gps_to_ptp_offset_c : integer := 315_964_819;
  
end package timestamp;

package body timestamp is

  function from_sl(
    second: in std_logic_vector;
    nanosecond: in std_logic_vector;
    abs_change: in std_logic) return timestamp_t
  is
    variable ret: timestamp_t;
  begin
    ret.second := unsigned(second);
    ret.nanosecond := unsigned(nanosecond);
    ret.abs_change := abs_change;
    return ret;
  end function;

  function second_slv(ts: timestamp_t) return std_logic_vector
  is
  begin
    return std_logic_vector(ts.second);
  end function;
  
  function nanosecond_slv(ts: timestamp_t) return std_logic_vector
  is
  begin
    return std_logic_vector(ts.nanosecond);
  end function;

  function abs_change_sl(ts: timestamp_t) return std_logic
  is
  begin
    return ts.abs_change;
  end function;

end package body;
