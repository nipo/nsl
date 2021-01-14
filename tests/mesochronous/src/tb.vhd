library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math, nsl_simulation, nsl_clocking;

entity tb is
end tb;

architecture arch of tb is

  constant data_width : integer := 8;

  signal counter, counter_delayed : unsigned(data_width-1 downto 0);
  signal done : std_ulogic_vector(0 to 0);
  signal reset_n, reset_n_async, clock, dclock : std_ulogic;

begin

  stim: process(reset_n, clock)
  begin
    if reset_n = '0' then
      counter <= (others => '0');
    elsif rising_edge(clock) then
      counter <= counter + 1;
    end if;
  end process;

  done_gen: process
  begin
    done <= "0";
    wait for 1000 us;
    done <= "1";
    wait;
  end process;

  resync: nsl_clocking.interdomain.interdomain_mesochronous_resync
    generic map(
      data_width_c => data_width
      )
    port map(
      clock_i(0) => clock,
      clock_i(1) => dclock,
      reset_n_i => reset_n,
      data_i => std_ulogic_vector(counter),
      unsigned(data_o) => counter_delayed
      );

  dclock <= clock after 40 ns;
  
  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done'length
      )
    port map(
      clock_period(0) => 100 ns,
      reset_duration(0) => 150 ns,
      reset_n_o(0) => reset_n,
      clock_o(0) => clock,
      done_i => done
      );
  
end;
