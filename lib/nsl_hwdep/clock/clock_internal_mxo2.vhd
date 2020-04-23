library ieee;
use ieee.std_logic_1164.all;

library machxo2;

entity clock_internal is
  port(
    clock_o      : out std_ulogic
    );
end entity;

architecture mxo2 of clock_internal is

  attribute NOM_FREQ : string;
  attribute NOM_FREQ of inst : label is "66.5";
  
begin

  inst : machxo2.components.osch
    -- synthesis translate_off
    generic map(
      nom_freq => "66.5"
      )
    -- synthesis translate_on
    port map(
      stdby => '0',
      sedstdby => open,
      osc   => clock_o
      );
    
end architecture;
