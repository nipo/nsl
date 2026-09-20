library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_simulation, nsl_io;

-- A DDR output that can let go of its pin, read back by a DDR input on
-- the same wire.  The output drives in bursts and releases in between,
-- so the turnaround is exercised rather than a steady drive.
--
-- Checks that the pattern comes back, and that the wire is left
-- floating on the periods where nobody drives it.
entity tb is
end entity;

architecture beh of tb is

  constant period_c: time := 10 ns;
  -- Two periods pass between a word going out and coming back: one on
  -- the wire, one in the capture pipeline.
  constant latency_c: natural := 2;
  constant trace_delay_c: time := 1 ns;

  signal clock_s: std_ulogic := '0';
  signal clock_pair_s: nsl_io.diff.diff_pair;
  signal stopped_s: boolean := false;

  signal d_s: std_ulogic_vector(1 downto 0) := (others => '0');
  signal oe_s: std_ulogic := '0';
  signal captured_s: std_ulogic_vector(1 downto 0);

  signal pad_s: nsl_io.io.tristated;
  signal wire_s: std_logic;
  signal wire_delayed_s: std_logic;
  signal pad_value_s: std_ulogic;

  type word_vector is array (natural range <>) of std_ulogic_vector(1 downto 0);
  signal history_s: word_vector(0 to latency_c) := (others => "00");
  signal driving_s: std_ulogic_vector(0 to latency_c) := (others => '0');

  -- The checks run in their own processes, so each keeps its own
  -- count and the end of the run asserts on the sum.  A report alone
  -- does not fail a run.
  signal loopback_error_s: natural := 0;
  signal float_error_s: natural := 0;

begin

  clock_s <= (not clock_s) after period_c / 2 when not stopped_s else '0';
  clock_pair_s.p <= clock_s;
  clock_pair_s.n <= not clock_s;

  wire_s <= nsl_io.io.to_logic(pad_s);
  wire_s <= 'L';
  wire_delayed_s <= transport wire_s after trace_delay_c;
  pad_value_s <= to_x01(wire_delayed_s);

  driver: nsl_io.ddr.ddr_output_tristated
    port map(
      clock_i => clock_pair_s,
      d_i => d_s,
      oe_i => oe_s,
      pad_o => pad_s
      );

  listener: nsl_io.ddr.ddr_input
    port map(
      clock_i => clock_pair_s,
      dd_i => pad_value_s,
      d_o => captured_s
      );

  -- What the input should be seeing now went out latency_c periods
  -- ago, so keep that many words around.
  delay_line: process(clock_s) is
  begin
    if rising_edge(clock_s) then
      history_s(1 to latency_c) <= history_s(0 to latency_c - 1);
      history_s(0) <= d_s;
      driving_s(1 to latency_c) <= driving_s(0 to latency_c - 1);
      driving_s(0) <= oe_s;
    end if;
  end process;

  stim: process is
    variable pattern: unsigned(1 downto 0);
  begin
    oe_s <= '0';
    for i in 1 to 4
    loop
      wait until falling_edge(clock_s);
    end loop;

    for cycle in 0 to 63
    loop
      wait until falling_edge(clock_s);
      if (cycle / 4) mod 2 = 0 then
        pattern := to_unsigned((cycle * 7 + 1) mod 4, 2);
        d_s <= std_ulogic_vector(pattern);
        oe_s <= '1';
      else
        d_s <= "00";
        oe_s <= '0';
      end if;
    end loop;

    oe_s <= '0';
    for i in 1 to 8
    loop
      wait until falling_edge(clock_s);
    end loop;

    report "ddr output tristate loopback done, "
      & integer'image(loopback_error_s) & " mismatches, "
      & integer'image(float_error_s) & " undriven periods held";

    assert loopback_error_s + float_error_s = 0
      report "ddr output tristate bench found "
      & integer'image(loopback_error_s + float_error_s) & " errors"
      severity failure;

    stopped_s <= true;
    nsl_simulation.control.terminate(0);
    wait;
  end process;

  check: process is
    variable errors: natural := 0;
  begin
    wait until rising_edge(clock_s);

    if driving_s(latency_c) = '1' and captured_s /= history_s(latency_c) then
      errors := errors + 1;
      loopback_error_s <= errors;
      report "loopback mismatch at " & time'image(now)
        severity error;
    end if;
  end process;

  float: process is
    variable errors: natural := 0;
  begin
    wait until rising_edge(clock_s);
    wait for period_c / 4;

    if driving_s(0) = '0' and driving_s(1) = '0' and wire_s /= 'L' then
      errors := errors + 1;
      float_error_s <= errors;
      report "wire should be floating while nobody drives it"
        severity error;
    end if;
  end process;

end architecture;
