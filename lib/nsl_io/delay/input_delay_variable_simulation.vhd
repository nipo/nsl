library ieee;
use ieee.std_logic_1164.all;

entity input_delay_variable is
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;
    mark_o : out std_ulogic;
    shift_i : in std_ulogic;

    data_i : in std_ulogic;
    data_o : out std_ulogic
    );
end entity;

architecture sim of input_delay_variable is

  constant tap_time_c : time := 57 ps;
  constant tap_step_count_c : integer := 64;
  signal step_count_s: integer range 0 to tap_step_count_c-1;

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      if shift_i = '1' then
        if step_count_s = 0 then
          step_count_s <= tap_step_count_c-1;
        else
          step_count_s <= step_count_s - 1;
        end if;
      end if;
    end if;

    if reset_n_i = '0' then
      step_count_s <= 0;
    end if;
  end process;

  mark_o <= '1' when step_count_s = 0 else '0';
  data_o <= data_i after (step_count_s * tap_time_c);
  
end architecture;
