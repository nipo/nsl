library ieee;
use ieee.std_logic_1164.all;

entity clock_output is
  port(
    p_clk     : in  std_ulogic;
    p_clk_neg : in  std_ulogic;
    p_port    : out std_ulogic
    );
end entity;

architecture gen of clock_output is
  
begin

  p_port <= p_clk;

end architecture;
