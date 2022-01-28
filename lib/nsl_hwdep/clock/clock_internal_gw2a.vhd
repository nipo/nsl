 library ieee;
use ieee.std_logic_1164.all;

entity clock_internal is
  port(
    clock_o      : out std_ulogic
    );
end entity;

architecture gw of clock_internal is

  constant target_freq_c : integer := 65;
  
  -- 2.1-125 MHz, 5%
  -- freq_div: 2-128, even only
  -- Aim for ~60MHz
  
  COMPONENT OSC
    GENERIC (
      FREQ_DIV: in integer := 100
    );
    port (
      OSCOUT: out std_logic
    );
  END COMPONENT;

begin

  inst: osc
    generic map (
      freq_div => (250 / target_freq_c / 2) * 2
      )
    port map (
      oscout => clock_o
      );

end architecture;
