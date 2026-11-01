library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_simulation, nsl_transceiver;
use nsl_transceiver.lane.all;
use nsl_simulation.driver.all;

-- The fabric pattern generator and checker over the library's plain
-- IO serialiser and deserialiser, with no transceiver anywhere: a
-- pattern put on a pad N bits at a time and read back off one M bits
-- at a time.
--
-- The two widths are different in every case here. That is the
-- point: a pattern is a bit stream, and both ends of this bench
-- disagree about how many of its bits a word holds and about where a
-- word starts, which leaves them agreeing on nothing but the order
-- the bits go out in.
entity tb is
end tb;

architecture arch of tb is

  -- One bit period, and a word period per width in use.
  constant bit_period_c : time := 1 ns;

  signal bit_clock_s, clock8_s, clock10_s : std_ulogic;
  signal reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 2);

begin

  -- A whole received word of cable, in quarter bit steps, so every
  -- phase within a bit and every word boundary the deserialiser can
  -- land on is visited. Which one it lands on is not something the
  -- bench arranges and not something the checker is told.
  narrow_to_wide: entity work.serdes_bench
    generic map(
      tx_ratio_c => 8,
      rx_ratio_c => 10,
      mode_c => PRBS_7,
      step_count_c => 40,
      step_c => 250 ps,
      label_c => "8 bit out, 10 bit in"
      )
    port map(
      bit_clock_i => bit_clock_s,
      tx_clock_i => clock8_s,
      rx_clock_i => clock10_s,
      reset_n_i => reset_n_s,
      done_o => done_s(0)
      );

  wide_to_narrow: entity work.serdes_bench
    generic map(
      tx_ratio_c => 10,
      rx_ratio_c => 8,
      mode_c => PRBS_23,
      step_count_c => 40,
      step_c => 250 ps,
      label_c => "10 bit out, 8 bit in"
      )
    port map(
      bit_clock_i => bit_clock_s,
      tx_clock_i => clock10_s,
      rx_clock_i => clock8_s,
      reset_n_i => reset_n_s,
      done_o => done_s(1)
      );

  -- And the same link with the deserialiser handing its word over
  -- the other way round. A bench that passed this too would be
  -- proving nothing about the first two: it is the one thing the
  -- ends cannot differ on.
  reversed: entity work.serdes_bench
    generic map(
      tx_ratio_c => 8,
      rx_ratio_c => 10,
      mode_c => PRBS_7,
      agree_c => false,
      step_count_c => 2,
      step_c => 250 ps,
      label_c => "reversed bit order"
      )
    port map(
      bit_clock_i => bit_clock_s,
      tx_clock_i => clock8_s,
      rx_clock_i => clock10_s,
      reset_n_i => reset_n_s,
      done_o => done_s(2)
      );

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 3,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period => time_vector'(0 => bit_period_c,
                                   1 => bit_period_c * 8,
                                   2 => bit_period_c * 10),
      reset_duration(0) => bit_period_c * 40,
      reset_n_o(0) => reset_n_s,
      clock_o(0) => bit_clock_s,
      clock_o(1) => clock8_s,
      clock_o(2) => clock10_s,
      done_i => done_s
      );

end;
