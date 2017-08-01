library ieee;
use ieee.std_logic_1164.all;

library unisim;
use unisim.vcomponents.all;

entity clock_internal is
  port(
    p_clk      : out std_ulogic
    );
end entity;

architecture sp6 of clock_internal is
  
begin

  inst : startup_spartan6
   port map (
     cfgmclk => p_clk,
     clk => '0',
     gsr => '0',
     gts => '0',
     keyclearb => '0'
   );

end architecture;
