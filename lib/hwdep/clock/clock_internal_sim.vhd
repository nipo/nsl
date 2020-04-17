library ieee;
use ieee.std_logic_1164.all;

entity clock_internal is
  port(
    p_clk      : out std_ulogic
    );
end entity;

architecture sim of clock_internal is

  signal clock: std_ulogic := '0';

begin

  p_clk <= clock;
  clock <= not clock after 15 ns;

end architecture;
