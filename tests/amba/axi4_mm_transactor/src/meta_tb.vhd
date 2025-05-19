library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_simulation, work;

entity meta_tb is
end meta_tb;

architecture arch of meta_tb is

  constant count_c: integer := 23;

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s: std_ulogic_vector(1 to count_c);
  
begin

  all_tbs: for i in 1 to count_c
  generate
    tb_inst: work.tester.tb
      generic map(
        beat_count_c => i
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,
        done_o => done_s(i)
        );
  end generate;
  
  simdrv: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 10 ns,
      reset_duration => (others => 25 ns),
      clock_o(0) => clock_s,
      reset_n_o(0) => reset_n_s,
      done_i => done_s
      );

end;
