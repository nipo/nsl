library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package calendar is

  -- Proleptic Gregorian date and time of day.
  type date_time_t is
  record
    year : unsigned(11 downto 0);
    -- 1 to 12
    month : unsigned(3 downto 0);
    -- 1 to 31
    day : unsigned(4 downto 0);
    hour : unsigned(4 downto 0);
    minute : unsigned(5 downto 0);
    second : unsigned(5 downto 0);
  end record;

  -- Converts a count of seconds elapsed since 00:00:00 on January
  -- 1st of epoch_year_c into date and time of day (NTP era 0 with
  -- the default epoch).  Free running: a conversion of the current
  -- input starts as soon as the previous one completes, and takes a
  -- few hundred cycles.  valid_o strobes for one cycle each time
  -- date_time_o is updated.
  component calendar_from_seconds is
    generic(
      epoch_year_c : natural := 1900
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      seconds_i : in unsigned(31 downto 0);

      date_time_o : out date_time_t;
      valid_o : out std_ulogic
      );
  end component;

end package;
