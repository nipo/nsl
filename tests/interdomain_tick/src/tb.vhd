library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_clocking, nsl_simulation;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;

entity tb is
end tb;

architecture arch of tb is

  -- Ticks carried in each direction.  An odd count leaves the input
  -- bistable set, which is what the reset of the last phase has to
  -- clear without the output side mistaking it for a tick.
  constant tick_count_c: natural := 7;

  -- Cycles of the slower clock between two input ticks: the crossing
  -- carries at most one tick per two cycles of either domain.
  constant spacing_c: natural := 3;

  signal fast_clock_s, slow_clock_s: std_ulogic;
  signal driver_reset_n_s, held_reset_n_s, reset_n_s: std_ulogic;

  signal up_in_s, up_out_s: std_ulogic;
  signal down_in_s, down_out_s: std_ulogic;

  -- Never cleared: the last phase compares them across a reset.
  signal up_count_s: natural := 0;
  signal down_count_s: natural := 0;

  signal done_s: std_ulogic_vector(0 to 0);

begin

  reset_n_s <= driver_reset_n_s and held_reset_n_s;

  up: nsl_clocking.interdomain.interdomain_tick
    port map(
      input_clock_i => fast_clock_s,
      output_clock_i => slow_clock_s,
      input_reset_n_i => reset_n_s,
      tick_i => up_in_s,
      tick_o => up_out_s
      );

  down: nsl_clocking.interdomain.interdomain_tick
    port map(
      input_clock_i => slow_clock_s,
      output_clock_i => fast_clock_s,
      input_reset_n_i => reset_n_s,
      tick_i => down_in_s,
      tick_o => down_out_s
      );

  up_watch: process(slow_clock_s) is
  begin
    if rising_edge(slow_clock_s) then
      if up_out_s = '1' then
        up_count_s <= up_count_s + 1;
      end if;
    end if;
  end process;

  down_watch: process(fast_clock_s) is
  begin
    if rising_edge(fast_clock_s) then
      if down_out_s = '1' then
        down_count_s <= down_count_s + 1;
      end if;
    end if;
  end process;

  stim: process is
    variable up_before_v, down_before_v: natural;
  begin
    done_s(0) <= '0';
    up_in_s <= '0';
    down_in_s <= '0';
    held_reset_n_s <= '1';

    wait until reset_n_s = '1';

    -- Coming out of reset is not a tick, however the output side
    -- settles.
    for i in 1 to 8
    loop
      wait until falling_edge(slow_clock_s);
    end loop;

    assert_equal("ticks out of reset, fast to slow", up_count_s, 0, failure);
    assert_equal("ticks out of reset, slow to fast", down_count_s, 0, failure);

    -- One output tick per input tick, in both clock ratios.
    for index in 1 to tick_count_c
    loop
      wait until falling_edge(fast_clock_s);
      up_in_s <= '1';
      wait until falling_edge(fast_clock_s);
      up_in_s <= '0';

      wait until falling_edge(slow_clock_s);
      down_in_s <= '1';
      wait until falling_edge(slow_clock_s);
      down_in_s <= '0';

      for i in 1 to spacing_c
      loop
        wait until falling_edge(slow_clock_s);
      end loop;
    end loop;

    assert_equal("ticks carried, fast to slow", up_count_s, tick_count_c, failure);
    assert_equal("ticks carried, slow to fast", down_count_s, tick_count_c, failure);

    -- Reset clears the input bistable from wherever it stands, which
    -- the output side must not read as one more tick.
    up_before_v := up_count_s;
    down_before_v := down_count_s;

    wait until falling_edge(fast_clock_s);
    held_reset_n_s <= '0';

    for i in 1 to 4
    loop
      wait until falling_edge(slow_clock_s);
    end loop;

    held_reset_n_s <= '1';

    for i in 1 to 8
    loop
      wait until falling_edge(slow_clock_s);
    end loop;

    assert_equal("ticks across a reset, fast to slow",
                 up_count_s, up_before_v, failure);
    assert_equal("ticks across a reset, slow to fast",
                 down_count_s, down_before_v, failure);

    -- The crossing still works once the reset is behind it.
    wait until falling_edge(fast_clock_s);
    up_in_s <= '1';
    wait until falling_edge(fast_clock_s);
    up_in_s <= '0';

    wait until falling_edge(slow_clock_s);
    down_in_s <= '1';
    wait until falling_edge(slow_clock_s);
    down_in_s <= '0';

    for i in 1 to spacing_c
    loop
      wait until falling_edge(slow_clock_s);
    end loop;

    assert_equal("ticks after a reset, fast to slow",
                 up_count_s, up_before_v + 1, failure);
    assert_equal("ticks after a reset, slow to fast",
                 down_count_s, down_before_v + 1, failure);

    log_info("Tick crossing scenarios passed");

    done_s(0) <= '1';
    wait;
  end process;

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 2,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 10 ns,
      clock_period(1) => 27 ns,
      reset_duration(0) => 15 ns,
      reset_n_o(0) => driver_reset_n_s,
      clock_o(0) => fast_clock_s,
      clock_o(1) => slow_clock_s,
      done_i => done_s
      );

end;
