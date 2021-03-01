library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_simulation, nsl_math, nsl_semtech;
use nsl_semtech.sc202.all;
use nsl_math.fixed.all;

entity tb is
end tb;

architecture arch of tb is

  signal s_reset_n, s_clock, s_done : std_ulogic;
  signal s_value_f : ufixed(0 downto -7);
  signal s_value_r, s_expected_r : real;
  signal s_ctl: std_ulogic_vector(3 downto 0);
  
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

  sc: sc202_driver
    generic map(
      voltage_i_scale_c => 3.0
      )
    port map(
      clock_i => s_clock,
      reset_n_i => s_reset_n,

      voltage_i => s_value_f,

      vsel_o => s_ctl
      );
  
  stim: process
  begin
    s_done <= '0';
    wait for 30 ns;

    for i in 0 to 2 ** s_value_f'length - 1
    loop
      s_value_f <= ufixed(to_unsigned(i, s_value_f'length));
      s_value_r <= to_real(s_value_f);
      s_expected_r <= to_real(s_value_f) * 3.0;
      wait for 30 ns;
    end loop;
    
    s_done <= '1';
    wait;
  end process;
  
end;
