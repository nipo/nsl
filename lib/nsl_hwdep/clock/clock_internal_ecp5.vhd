library ieee;
use ieee.std_logic_1164.all;

entity clock_internal is
  port(
    clock_o      : out std_ulogic
    );
end entity;

architecture ecp5 of clock_internal is

  COMPONENT OSCG
      GENERIC (DIV: integer := 128);
      PORT (OSC : OUT std_logic);
  END COMPONENT;
  
begin

  inst : oscg
    generic map(
      div => 310/55
      )
    port map(
      osc   => clock_o
      );
    
end architecture;
