library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_sensor;
use nsl_sensor.stepper.all;

entity step_divisor is
  generic (
    divisor_c : natural := 2
    );
  port (
    reset_n_i     : in  std_ulogic;
    clock_i       : in  std_ulogic;

    step_i        : in step;
    step_o        : out step
    );
end entity;

architecture beh of step_divisor is

  signal value : natural range 0 to divisor_c-1;

begin

  regs: process(reset_n_i, clock_i)
  begin
    if reset_n_i = '0' then
      value <= 0;
    elsif rising_edge(clock_i) then
      step_o <= STEP_STABLE;
      if step_i = STEP_INCREMENT then
        if value /= divisor_c - 1 then
          value <= value + 1;
        else
          value <= 0;
          step_o <= STEP_INCREMENT;
        end if;
      elsif step_i = STEP_DECREMENT then
        if value /= 0 then
          value <= value - 1;
        else
          value <= divisor_c - 1;
          step_o <= STEP_DECREMENT;
        end if;
      end if;
    end if;
  end process;
  
end architecture;
