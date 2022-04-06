library ieee;
use ieee.std_logic_1164.all;

entity input_delay_fixed is
  generic(
    delay_ps_c: integer;
    is_ddr_c: boolean := true
    );
  port(
    data_i : in std_ulogic;
    data_o : out std_ulogic
    );
end entity;

architecture sim of input_delay_fixed is

  constant delay_time_c : time := delay_ps_c * 1 ps;

begin

  has_delay: if delay_ps_c /= 0
  generate
    data_o <= data_i after delay_time_c;
  end generate;

  no_delay: if delay_ps_c = 0
  generate
    data_o <= data_i;
  end generate;
  
end architecture;
