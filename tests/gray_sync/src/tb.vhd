library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math, nsl_simulation, nsl_clocking;

entity tb is
end tb;

architecture arch of tb is

  constant data_width : integer := 8;
  constant latency : integer := 3;
  subtype bin_t is unsigned(data_width-1 downto 0);
  subtype gray_t is std_ulogic_vector(data_width-1 downto 0);
  signal done : std_ulogic_vector(0 to 0);
  signal reset_n, reset_n_async, clock : std_ulogic;
  signal counter, counter_delayed : bin_t;
  signal counter_gray : gray_t;
  signal dec_pipelined : bin_t;

begin

  reset_sync_clk: nsl_clocking.async.async_edge
    port map(
      data_i => reset_n_async,
      data_o => reset_n,
      clock_i => clock
      );

  stim: process(reset_n, clock)
  begin
    if reset_n = '0' then
      counter <= (others => '0');
    elsif rising_edge(clock) then
      counter <= counter + 1;
    end if;
  end process;

  checker: process(clock)
  begin
    if rising_edge(clock) then
      nsl_simulation.assertions.assert_equal(
        "Both gray calculation",
        dec_pipelined, counter_delayed,
        note);
      if counter = (counter'range => '1') then
        done(0) <= '1';
      else
        done(0) <= '0';
      end if;
    end if;
  end process;

  counter_gray <= nsl_math.gray.bin_to_gray(counter);

  pipe: nsl_clocking.intradomain.intradomain_multi_reg
    generic map(
      cycle_count_c => latency,
      data_width_c => data_width
      )
    port map(
      clock_i => clock,
      data_i => std_ulogic_vector(counter),
      unsigned(data_o) => counter_delayed
      );

  decoder: nsl_math.gray.gray_decoder_pipelined
    generic map(
      cycle_count_c => latency,
      data_width_c => data_width
      )
    port map(
      clock_i => clock,
      gray_i => counter_gray,
      binary_o => dec_pipelined
      );
  
  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done'length
      )
    port map(
      clock_period(0) => 100 ns,
      reset_duration(0) => 100 ns,
      reset_n_o(0) => reset_n_async,
      clock_o(0) => clock,
      done_i => done
      );
  
end;
