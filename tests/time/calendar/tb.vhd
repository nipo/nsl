library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_time, nsl_data;
use nsl_time.calendar.all;
use nsl_data.text.all;

entity tb is
end entity;

architecture sim of tb is

  type vector_t is
  record
    seconds : unsigned(31 downto 0);
    year, month, day, hour, minute, second : natural;
  end record;

  type vector_vector is array (natural range <>) of vector_t;

  constant vectors_c : vector_vector := (
    (x"00000000", 1900, 1, 1, 0, 0, 0),
    (x"004dc87f", 1900, 2, 28, 23, 59, 59),
    (x"004dc880", 1900, 3, 1, 0, 0, 0),
    (x"83aa7e80", 1970, 1, 1, 0, 0, 0),
    (x"bc17c1ff", 1999, 12, 31, 23, 59, 59),
    (x"bc658a80", 2000, 2, 29, 0, 0, 0),
    (x"bc66dc00", 2000, 3, 1, 0, 0, 0),
    (x"e98b98ff", 2024, 2, 29, 23, 59, 59),
    (x"ee44f7a6", 2026, 9, 4, 7, 54, 14),
    (x"ffffffff", 2036, 2, 7, 6, 28, 15)
    );

  signal clock_s : std_ulogic := '0';
  signal reset_n_s : std_ulogic := '0';
  signal done_s : boolean := false;

  signal seconds_s : unsigned(31 downto 0) := (others => '0');
  signal date_time_s : date_time_t;
  signal valid_s : std_ulogic;

begin

  dut: calendar_from_seconds
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      seconds_i => seconds_s,
      date_time_o => date_time_s,
      valid_o => valid_s
      );

  clock_gen: process
  begin
    while not done_s loop
      clock_s <= '0';
      wait for 5 ns;
      clock_s <= '1';
      wait for 5 ns;
    end loop;
    wait;
  end process;

  stim: process
    variable v : vector_t;
    variable ok : boolean;
  begin
    assert to_decimal_string(to_unsigned(2026, 12), 4) = "2026"
      report "decimal 2026 -> " & to_decimal_string(to_unsigned(2026, 12), 4)
      severity failure;
    assert to_decimal_string(to_unsigned(7, 8), 2) = "07"
      report "decimal 7 -> " & to_decimal_string(to_unsigned(7, 8), 2)
      severity failure;
    assert to_decimal_string(to_unsigned(155, 8), 3) = "155"
      report "decimal 155 -> " & to_decimal_string(to_unsigned(155, 8), 3)
      severity failure;
    assert to_decimal_string(to_unsigned(255, 8), 3) = "255"
      report "decimal 255 -> " & to_decimal_string(to_unsigned(255, 8), 3)
      severity failure;
    assert to_decimal_string(to_unsigned(0, 8), 3) = "000"
      report "decimal 0 -> " & to_decimal_string(to_unsigned(0, 8), 3)
      severity failure;
    assert to_decimal_string(to_unsigned(1234, 12), 2) = "34"
      report "decimal 1234 truncated -> " & to_decimal_string(to_unsigned(1234, 12), 2)
      severity failure;

    wait for 30 ns;
    reset_n_s <= '1';

    for i in vectors_c'range loop
      v := vectors_c(i);
      seconds_s <= v.seconds;
      -- A conversion may be in flight with the previous input: the
      -- second completion is the one started after the change.
      for n in 1 to 2 loop
        loop
          wait until rising_edge(clock_s);
          exit when valid_s = '1';
        end loop;
      end loop;

      ok := to_integer(date_time_s.year) = v.year
        and to_integer(date_time_s.month) = v.month
        and to_integer(date_time_s.day) = v.day
        and to_integer(date_time_s.hour) = v.hour
        and to_integer(date_time_s.minute) = v.minute
        and to_integer(date_time_s.second) = v.second;

      report to_hex_string(std_ulogic_vector(v.seconds)) & " -> "
        & to_decimal_string(date_time_s.year, 4) & "-"
        & to_decimal_string(date_time_s.month, 2) & "-"
        & to_decimal_string(date_time_s.day, 2) & " "
        & to_decimal_string(date_time_s.hour, 2) & ":"
        & to_decimal_string(date_time_s.minute, 2) & ":"
        & to_decimal_string(date_time_s.second, 2)
        & if_else(ok, " OK", " MISMATCH");

      assert ok
        report "Conversion mismatch for " & to_hex_string(std_ulogic_vector(v.seconds))
        severity failure;
    end loop;

    report "calendar_from_seconds testbench PASSED";
    done_s <= true;
    wait;
  end process;

end architecture;
