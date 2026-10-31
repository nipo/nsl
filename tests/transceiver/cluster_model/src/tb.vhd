library ieee;
use ieee.std_logic_1164.all;

library nsl_simulation, nsl_transceiver;
use nsl_transceiver.lane.all;

-- The behavioural cluster backend is the only transceiver backend
-- that can be simulated: the Gowin quad has no model at all, and the
-- Xilinx channels need a vendor library. Everything the portable
-- contract promises a lane does is therefore checked here, against a
-- model of a quad rather than against a primitive.
--
-- Each block below is a whole link: a lane that has to lock its PLL,
-- find the comma in a stream it joined mid-flight, fill its elastic
-- buffer, and then carry framed bytes back without losing one.
entity tb is
end tb;

architecture arch of tb is

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 4);

begin

  -- The widths a lane is built in, each at the rate that makes its
  -- word clock the 125 MHz reference: a gearbox or a word size the
  -- model got wrong shows up as a frame that arrives shifted.
  one_byte: entity work.link_bench
    generic map(
      data_byte_count_c => 1,
      line_rate_mbps_c => 1250,
      label_c => "1 byte lane"
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      done_o => done_s(0)
      );

  two_byte: entity work.link_bench
    generic map(
      data_byte_count_c => 2,
      line_rate_mbps_c => 2500,
      label_c => "2 byte lane"
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      done_o => done_s(1)
      );

  four_byte: entity work.link_bench
    generic map(
      data_byte_count_c => 4,
      line_rate_mbps_c => 5000,
      label_c => "4 byte lane"
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      done_o => done_s(2)
      );

  -- A pair wired the wrong way round, undone at both ends by the
  -- lane's own polarity settings.
  inverted: entity work.link_bench
    generic map(
      data_byte_count_c => 1,
      line_rate_mbps_c => 1250,
      polarity_invert_c => true,
      label_c => "inverted lane"
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      done_o => done_s(3)
      );

  -- The same swapped pair, this time undone on the receive side by
  -- the comma setting instead, which is what a transceiver without a
  -- runtime polarity invert has to use.
  negated_comma: entity work.link_bench
    generic map(
      data_byte_count_c => 1,
      line_rate_mbps_c => 1250,
      polarity_invert_c => true,
      comma_negated_c => true,
      label_c => "negated comma lane"
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      done_o => done_s(4)
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
