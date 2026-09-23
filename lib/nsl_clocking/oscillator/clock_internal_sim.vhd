library ieee;
use ieee.std_logic_1164.all;

entity clock_internal is
  port(
    clock_o      : out std_ulogic
    );
end entity;

architecture sim of clock_internal is

  signal clock: std_ulogic := '0';

begin

  clock_o <= clock;
  clock <= not clock after 15 ns;

end architecture;
