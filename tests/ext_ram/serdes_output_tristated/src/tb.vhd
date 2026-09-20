library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_simulation, nsl_io;

-- A serialising output that can let go of its pin.
--
-- What this block adds over a plain serialiser is the enable path, so
-- that is what gets checked: every enable pattern is driven in turn
-- and the wire is watched over whole words.  An enable bit covers two
-- serial bits, so a pattern with n bits set must drive the wire for
-- exactly 2n slots out of the word and leave it alone for the rest.
--
-- Counting over whole words keeps this independent of where the word
-- happens to sit against the parallel clock, which is an
-- implementation's business rather than a property worth pinning.
entity tb is
end entity;

architecture beh of tb is

  constant ratio_c: natural := 8;
  constant serial_period_c: time := 2500 ps;
  constant word_count_c: natural := 8;

  signal serial_clock_s: std_ulogic := '0';
  signal parallel_clock_s: std_ulogic := '0';
  signal reset_n_s: std_ulogic := '0';
  signal stopped_s: boolean := false;

  signal parallel_s: std_ulogic_vector(0 to ratio_c-1) := (others => '0');
  signal enable_s: std_ulogic_vector(0 to ratio_c/2-1) := (others => '0');
  signal pad_s: nsl_io.io.tristated;
  signal wire_s: std_logic;

  signal counting_s: boolean := false;
  signal driven_s: natural := 0;
  signal floating_s: natural := 0;
  signal seen_high_s: boolean := false;
  signal seen_low_s: boolean := false;

begin

  serial_clock_s <= (not serial_clock_s) after serial_period_c / 2
                    when not stopped_s else '0';

  parallel_gen: process is
  begin
    while not stopped_s
    loop
      wait for serial_period_c * ratio_c / 4;
      parallel_clock_s <= not parallel_clock_s;
    end loop;
    wait;
  end process;

  dut: nsl_io.serdes.serdes_output_tristated
    generic map(
      left_first_c => true,
      ddr_mode_c => true,
      ratio_c => ratio_c
      )
    port map(
      serial_clock_i => serial_clock_s,
      parallel_clock_i => parallel_clock_s,
      reset_n_i => reset_n_s,
      parallel_i => parallel_s,
      output_enable_i => enable_s,
      pad_o => pad_s
      );

  wire_s <= nsl_io.io.to_logic(pad_s);
  wire_s <= 'L';

  -- One sample per serial slot, taken away from the edges.
  sampler: process is
    variable was_counting: boolean := false;
    variable driven, floating: natural;
    variable high, low: boolean;
  begin
    wait until rising_edge(serial_clock_s) or falling_edge(serial_clock_s);
    wait for serial_period_c / 8;

    driven := 0;
    floating := 0;
    high := false;
    low := false;

    if wire_s = 'L' then
      floating := 1;
    else
      driven := 1;
      high := wire_s = '1';
      low := wire_s = '0';
    end if;

    if counting_s and not was_counting then
      -- The slot the count opens on belongs to it too.
      driven_s <= driven;
      floating_s <= floating;
      seen_high_s <= high;
      seen_low_s <= low;
    elsif counting_s then
      driven_s <= driven_s + driven;
      floating_s <= floating_s + floating;
      seen_high_s <= seen_high_s or high;
      seen_low_s <= seen_low_s or low;
    end if;

    was_counting := counting_s;
  end process;

  stim: process is
    variable expected_driven: natural;
    variable set_count: natural;
    -- A report alone does not fail a run, so failures are counted and
    -- the count is asserted on at the end.
    variable errors: natural := 0;
  begin
    reset_n_s <= '0';
    for i in 1 to 4
    loop
      wait until rising_edge(parallel_clock_s);
    end loop;
    reset_n_s <= '1';

    for pattern in 0 to 2 ** (ratio_c/2) - 1
    loop
      wait until rising_edge(parallel_clock_s);
      -- Alternating data, so a driven slot is never ambiguous with a
      -- floating one whatever the enable pattern.
      parallel_s <= "10110100";
      enable_s <= std_ulogic_vector(to_unsigned(pattern, ratio_c/2));

      -- Let the word reach the pin before counting anything.
      for i in 1 to 3
      loop
        wait until rising_edge(parallel_clock_s);
      end loop;

      wait until rising_edge(parallel_clock_s);
      counting_s <= true;

      for i in 1 to word_count_c
      loop
        wait until rising_edge(parallel_clock_s);
      end loop;
      counting_s <= false;
      wait for serial_period_c;

      set_count := 0;
      for i in 0 to ratio_c/2-1
      loop
        if enable_s(i) = '1' then
          set_count := set_count + 1;
        end if;
      end loop;
      expected_driven := set_count * 2 * word_count_c;

      if driven_s /= expected_driven then
        errors := errors + 1;
        report "enable pattern " & integer'image(pattern) & " drove "
          & integer'image(driven_s) & " slots, expected "
          & integer'image(expected_driven)
          severity error;
      end if;

      if driven_s + floating_s /= ratio_c * word_count_c then
        errors := errors + 1;
        report "enable pattern " & integer'image(pattern) & " accounted for "
          & integer'image(driven_s + floating_s) & " slots out of "
          & integer'image(ratio_c * word_count_c)
          severity error;
      end if;

      -- With anything driven at all, the data has to be moving rather
      -- than stuck at one level.
      if set_count = ratio_c/2 and not (seen_high_s and seen_low_s) then
        errors := errors + 1;
        report "the wire never carried both levels while fully enabled"
          severity error;
      end if;
    end loop;

    report "serdes tristate output done, " & integer'image(errors)
      & " failures";

    assert errors = 0
      report "serdes tristate output bench found " & integer'image(errors)
      & " failures"
      severity failure;

    stopped_s <= true;
    nsl_simulation.control.terminate(0);
    wait;
  end process;

end architecture;
