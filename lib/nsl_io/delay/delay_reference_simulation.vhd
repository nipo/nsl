library ieee;
use ieee.std_logic_1164.all;

entity delay_reference is
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    ready_o : out std_ulogic
    );
end entity;

architecture simulation of delay_reference is

begin

  ready_o <= reset_n_i;

end architecture;
