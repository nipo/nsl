library ieee;
use ieee.std_logic_1164.all;

library work;

entity output_delay_fixed is
  generic(
    delay_ps_c: integer;
    is_ddr_c: boolean := true
    );
  port(
    data_i : in std_ulogic;
    data_o : out std_ulogic
    );
end entity;

architecture symmetrical of output_delay_fixed is

begin

  b: work.delay.input_delay_fixed
    generic map(
      delay_ps_c => delay_ps_c,
      is_ddr_c => is_ddr_c
      )
    port map(
      data_i => data_i,
      data_o => data_o
      );
  
end architecture;
