library ieee;
use ieee.std_logic_1164.all;

library nsl_simulation;

-- An SGMII link's alignment loop has to converge whatever the cable
-- between the two ends does to the stream's phase. A board offers
-- one cable, so a length the loop cannot handle survives every test
-- run on hardware; the sweep below offers it every length inside a
-- word.
entity tb is
end tb;

architecture arch of tb is

  signal clock125_s, clock625_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 0);

begin

  -- A whole word period, in quarter-bit steps: every bit slip the
  -- serdes can be left on, and four phases inside each bit.
  full_sweep: entity work.channel_bench
    generic map(
      step_count_c => 40,
      step_c => 200 ps,
      label_c => "cable sweep"
      )
    port map(
      clock125_i => clock125_s,
      clock625_i => clock625_s,
      reset_n_i => reset_n_s,
      done_o => done_s(0)
      );

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 2,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 8 ns,
      clock_period(1) => 1600 ps,
      reset_duration(0) => 14 ns,
      reset_n_o(0) => reset_n_s,
      clock_o(0) => clock125_s,
      clock_o(1) => clock625_s,
      done_i => done_s
      );

end;
