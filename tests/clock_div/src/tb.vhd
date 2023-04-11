library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_io, nsl_simulation;

entity tb is
end tb;

architecture arch of tb is

  constant data_width : integer := 2;
  subtype word_t is std_ulogic_vector(data_width-1 downto 0);
  
  signal clock_s, reset_n_s : std_ulogic;
  signal generated_clock_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 0);
  
begin

  done_gen: process
  begin
    done_s <= "0";
    wait for 10 us;
    done_s <= "1";
    wait;
  end process;
  
  cko: nsl_io.clock.clock_output_se_divided
    generic map(
      divisor_c => 5
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      port_o => generated_clock_s
      );

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 5 ns,
      reset_duration(0) => 100 ns,
      reset_n_o(0) => reset_n_s,
      clock_o(0) => clock_s,
      done_i => done_s
      );
  
end;
