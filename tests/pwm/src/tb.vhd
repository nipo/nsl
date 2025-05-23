library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_signal_generator, nsl_simulation;
use nsl_simulation.assertions.all;

entity tb is
end tb;

architecture arch of tb is

  constant clock_hz_c : natural := 100e6;
  constant clock_period_c : time := 1000000000 ns / clock_hz_c;
  constant reset_period_c : time := clock_period_c * 7 / 2;
  signal clock_s : std_ulogic := '0';
  signal reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 0);

  signal pwm_s: std_ulogic;
  signal duty_s: unsigned(7 downto 0);
  
begin

  stim: process
  begin
    done_s(0) <= '0';
    duty_s <= x"00";

    wait for 10 us;
    
    duty_s <= x"80";

    wait for 10 us;

    duty_s <= x"C0";

    wait for 10 us;

    duty_s <= x"ff";

    wait for 10 us;

    done_s(0) <= '1';
    wait;
  end process;
  
  pwm: nsl_signal_generator.pwm.ss_pwm
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,

      pwm_o => pwm_s,

      duty_i => duty_s
      );
  
  
  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => clock_period_c,
      reset_duration(0) => reset_period_c,
      reset_n_o(0) => reset_n_s,
      clock_o(0) => clock_s,
      done_i => done_s
      );

end;
