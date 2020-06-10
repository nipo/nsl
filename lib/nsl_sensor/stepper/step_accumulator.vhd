library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_sensor;
use nsl_sensor.stepper.all;

entity step_accumulator is
  generic (
    counter_width_c : natural;
    allow_wrap_c : boolean := false
    );
  port (
    reset_n_i     : in  std_ulogic;
    clock_i       : in  std_ulogic;

    step_i        : in step;
    low_i         : in std_ulogic := '0';
    low_value_i   : in unsigned(counter_width_c-1 downto 0) := (others => '0');
    high_i        : in std_ulogic := '0';
    high_value_i  : in unsigned(counter_width_c-1 downto 0) := (others => '1');
    value_o       : out unsigned(counter_width_c-1 downto 0)
    );
end entity;

architecture beh of step_accumulator is

  signal value : unsigned(counter_width_c-1 downto 0);

begin

  regs: process(reset_n_i, clock_i)
  begin
    if reset_n_i = '0' then
      value <= (others => '0');
    elsif rising_edge(clock_i) then
      if low_i = '1' then
        value <= low_value_i;
      elsif high_i = '1' then
        value <= high_value_i;
      elsif step_i = STEP_INCREMENT and (allow_wrap_c or value /= high_value_i) then
        value <= value + 1;
      elsif step_i = STEP_DECREMENT and (allow_wrap_c or value /= low_value_i) then
        value <= value - 1;
      end if;
    end if;
  end process;

  value_o <= value;
  
end architecture;
