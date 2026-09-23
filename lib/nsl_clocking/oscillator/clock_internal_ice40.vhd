library ieee;
use ieee.std_logic_1164.all;

library sb_ice;

entity clock_internal is
  port(
    clock_o      : out std_ulogic
    );
end entity;

architecture ice of clock_internal is
  
begin

  inst : sb_ice.components.sb_hfosc
    port map(
      clkhfen => '1',
      clkhfpu => '1',
      clkhf   => clock_o
      );
    
end architecture;
