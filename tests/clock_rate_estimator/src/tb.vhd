library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb is
end tb;

library nsl_clocking, nsl_simulation, nsl_data;
use nsl_clocking.interdomain.all;
use nsl_simulation.assertions.all;
use nsl_data.text.all;

architecture arch of tb is

  signal done_s : std_ulogic_vector(0 to 0);
  signal clock_s, reset_n_clock_s, reset_n_async_s, measured_clock_s : std_ulogic;
  signal expected_rate_s, rate_s : unsigned(1 downto 0);

  type stim_t is
  record
    generated_rate : integer;
    detected_index : unsigned(1 downto 0);
  end record;

  type stim_vector_t is array (positive range <>) of stim_t;

  constant clock_hz_c : integer := 125e6;
  constant stim_c : stim_vector_t := (
    (  25e5, "01"),
    ( 25e6, "00"),
    (125e6, "10")
    );

begin

  generator: process
    variable clock_half_period : time;
  begin
    done_s(0) <= '0';
    wait for 100 ns;

    for i in stim_c'range
    loop
      clock_half_period := 500e6 ps / (stim_c(i).generated_rate / 1e3);

      expected_rate_s <= stim_c(i).detected_index;

      for j in 0 to stim_c(i).generated_rate / 1000 * 2
      loop
        measured_clock_s <= '0';
        wait for clock_half_period;
        measured_clock_s <= '1';
        wait for clock_half_period;
      end loop;

      assert_equal("Stimulus #" & to_string(i) & ", rate: " & to_string(stim_c(i).generated_rate) & "Hz",
                   "rate_index",
                   stim_c(i).detected_index, rate_s, WARNING); 
    end loop;


    done_s(0) <= '1';
    wait;
  end process;

  estimator: nsl_clocking.interdomain.clock_rate_estimator
    generic map(
      clock_hz_c => real(clock_hz_c),
      rate_choice_c => (25.0e6, 2.5e6, 125.0e6)
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_clock_s,
      measured_clock_i => measured_clock_s,
      rate_index_o => rate_s
      );
  
  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => (1e9 ps / (clock_hz_c / 1e3)),
      reset_duration(0) => 15 ns,
      reset_n_o(0) => reset_n_async_s,
      clock_o(0) => clock_s,
      done_i => done_s
      );

end;
