library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_simulation, nsl_hwdep, nsl_math;
use nsl_hwdep.xadc.all;
use nsl_math.fixed.all;

entity tb is
end tb;

architecture arch of tb is

  signal s_reset_n, s_clock, s_done : std_ulogic;
  constant config: nsl_hwdep.xadc.channel_config_vector(0 to 0) := (
    0 => (channel_no => channel_vaux10,
          enabled => true,
          averaged => false,
          bipolar => false,
          extended_settling_time => false)
    );
  signal s_value : value_vector(config'range);
  type real_vector is array(natural range <>) of real;
  signal s_value_f : real_vector(config'range);
  
begin

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => 1
      )
    port map(
      clock_period(0) => 5 ns,
      reset_duration(0) => 15 ns,
      reset_n_o(0) => s_reset_n,
      clock_o(0) => s_clock,
      done_i(0) => s_done
      );

  adc: xadc_continuous
    generic map(
      config_c => config,
      clock_i_hz_c => 200000000,
      target_sps_c => 1000000
      )
    port map(
      clock_i => s_clock,
      reset_n_i => s_reset_n,

      pin_i(0).p => '0',
      pin_i(0).n => '0',

      value_o => s_value
      );
  
  stim: process
  begin
    s_done <= '0';
    wait for 1 ms;
    s_done <= '1';
    wait;
  end process;

  convertor: for i in config'range
  generate
    s_value_f(i) <= to_real(s_value(i));
  end generate;
  
end;
