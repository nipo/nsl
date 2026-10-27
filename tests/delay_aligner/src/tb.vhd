library ieee;
use ieee.std_logic_1164.all;

library nsl_simulation, work;
use work.bench.all;

entity tb is
end tb;

architecture arch of tb is

  signal done_s : std_ulogic_vector(0 to 2);
  signal clock_s, reset_n_s : std_ulogic;

  -- Expected taps are the center of the plateau of maximal score
  -- around the line, rounded down, with the last plateau in sweep
  -- order on ties.
  constant long_c : scenario_vector := (
    -- Eye starting on the mark
    (eye => eye(64, 0, 5), slip => 0, tap => 2),
    (eye => eye(64, 20, 30), slip => 3, tap => 25),
    -- Eyes across the wrap
    (eye => eye(64, 60, 3), slip => 9, tap => 63),
    (eye => eye(64, 61, 1), slip => 4, tap => 63),
    (eye => eye(64, 26, 5), slip => 1, tap => 47),
    -- Bad tap inside the eye: scores dip over it
    (eye => eye(64, 3, 6) or eye(64, 8, 11), slip => 5, tap => 9),
    -- Short run on the side of the eye
    (eye => eye(64, 10, 11) or eye(64, 30, 40), slip => 2, tap => 35),
    -- Narrowest eye
    (eye => eye(64, 40, 40), slip => 6, tap => 40),
    (eye => eye(64, 0, 63), slip => 8, tap => any_c)
    );

  -- Line barely longer than the kernel's half width
  constant short4_c : scenario_vector := (
    0 => (eye => eye(4, 0, 1), slip => 2, tap => 0)
    );

  -- No delay line
  constant none_c : scenario_vector := (
    0 => (eye => eye(1, 0, 0), slip => 3, tap => 0)
    );

begin

  long: entity work.aligner_bench
    generic map(
      tap_count_c => 64,
      scenarios_c => long_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      done_o => done_s(0)
      );

  short4: entity work.aligner_bench
    generic map(
      tap_count_c => 4,
      scenarios_c => short4_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      done_o => done_s(1)
      );

  none: entity work.aligner_bench
    generic map(
      tap_count_c => 1,
      scenarios_c => none_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      done_o => done_s(2)
      );

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 10 ns,
      reset_duration(0) => 13 ns,
      reset_n_o(0) => reset_n_s,
      clock_o(0) => clock_s,
      done_i => done_s
      );

end;
