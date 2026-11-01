library ieee;
use ieee.std_logic_1164.all;

library nsl_simulation, nsl_transceiver;
use nsl_transceiver.lane.all;

-- A transceiver's test pattern is the measurement a link is brought
-- up with: it asks whether the line carries bits at all, before any
-- protocol is in a position to ask. Nothing in the library could
-- answer that, in either direction, until the lane contract carried
-- the pattern as a coding model of its own.
entity tb is
end tb;

architecture arch of tb is

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 2);

begin

  -- The shallowest pattern on the narrowest lane: eight bits of line
  -- per word, so the checker has a whole word of history to work
  -- with each cycle.
  narrow: entity work.link_bench
    generic map(
      data_byte_count_c => 1,
      line_rate_mbps_c => 1250,
      mode_c => PRBS_7,
      other_mode_c => PRBS_9,
      label_c => "1 byte prbs 7"
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      done_o => done_s(0)
      );

  -- The deepest pattern on the same narrow lane, which takes four
  -- words of line before the checker has seen enough to predict
  -- anything at all.
  narrow_deep: entity work.link_bench
    generic map(
      data_byte_count_c => 1,
      line_rate_mbps_c => 1250,
      mode_c => PRBS_31,
      other_mode_c => PRBS_23,
      label_c => "1 byte prbs 31"
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      done_o => done_s(1)
      );

  -- A lane wide enough that one word carries more of the pattern
  -- than the generator keeps history for.
  wide: entity work.link_bench
    generic map(
      data_byte_count_c => 4,
      line_rate_mbps_c => 5000,
      mode_c => PRBS_23,
      other_mode_c => PRBS_31,
      label_c => "4 byte prbs 23"
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
      clock_period(0) => 8 ns,
      reset_duration(0) => 20 ns,
      reset_n_o(0) => reset_n_s,
      clock_o(0) => clock_s,
      done_i => done_s
      );

end;
