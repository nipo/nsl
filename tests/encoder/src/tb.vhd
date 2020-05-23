library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_clocking, nsl_simulation, nsl_sensor;

entity tb is
end tb;

architecture arch of tb is

  constant data_width : integer := 8;
  signal done : std_ulogic_vector(0 to 0);
  signal reset_n, reset_n_async, clock : std_ulogic;
  signal step: nsl_sensor.stepper.step;
  signal encoded: std_ulogic_vector(0 to 1);
  signal acc: unsigned(data_width-1 downto 0);

  function incremented(v: std_ulogic_vector(0 to 1))
    return std_ulogic_vector is
    variable ret : std_ulogic_vector(0 to 1);
  begin
    ret := v;

    if ret(0) = ret(1) then
      ret(0) := not ret(0);
    else
      ret(1) := not ret(1);
    end if;
    return ret;
  end function;

  function decremented(v: std_ulogic_vector(0 to 1))
    return std_ulogic_vector is
    variable ret : std_ulogic_vector(0 to 1);
  begin
    ret := v;

    if ret(0) = ret(1) then
      ret(1) := not ret(1);
    else
      ret(0) := not ret(0);
    end if;
    return ret;
  end function;
  
begin

  reset_sync_clk: nsl_clocking.async.async_edge
    port map(
      data_i => reset_n_async,
      data_o => reset_n,
      clock_i => clock
      );

  stim: process
  begin
    encoded <= "00";
    wait for 200 ns;
    increment: for i in 0 to 30
    loop
      encoded <= incremented(encoded);
      wait for 200 ns;
    end loop;
    decrement: for i in 0 to 30
    loop
      encoded <= decremented(encoded);
      wait for 200 ns;
    end loop;
    done(0) <= '1';
  end process;

  decoder: nsl_sensor.quadrature.quadrature_decoder
    port map(
      reset_n_i => reset_n,
      clock_i => clock,

      encoded_i => encoded,
      step_o => step
      );

  accumulator: nsl_sensor.stepper.step_accumulator
    generic map(
      counter_width_c => data_width
      )
    port map(
      reset_n_i => reset_n,
      clock_i => clock,

      step_i => step,
      value_o => acc
      );
  
  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done'length
      )
    port map(
      clock_period(0) => 10 ns,
      reset_duration(0) => 15 ns,
      reset_n_o(0) => reset_n_async,
      clock_o(0) => clock,
      done_i => done
      );
  
end;
