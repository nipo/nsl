library ieee;
use ieee.std_logic_1164.all;

library work;

entity output_delay_variable is
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;
    mark_o : out std_ulogic;
    shift_i : in std_ulogic;

    data_i : in std_ulogic;
    data_o : out std_ulogic
    );
end entity;

architecture symmetrical of output_delay_variable is

begin

  b: work.delay.input_delay_variable
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      mark_o => mark_o,
      shift_i => shift_i,
      data_i => data_i,
      data_o => data_o
      );
  
end architecture;
