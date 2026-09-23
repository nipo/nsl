library ieee;
use ieee.std_logic_1164.all;

-- Cyclone 10 LP internal oscillator, the one the part runs active
-- serial configuration from.  It is only specified through the AS
-- DCLK it clocks, 20 to 40 MHz, and runs at about twice that: expect
-- up to 80 MHz.  Quartus models the atom as unable to run above about
-- 46 MHz.
entity clock_internal is
  port(
    clock_o      : out std_ulogic
    );
end entity;

architecture cyclone10lp of clock_internal is

  component cyclone10lp_oscillator is
    port(
      oscena : in std_logic;
      clkout : out std_logic
      );
  end component;

begin

  gen: cyclone10lp_oscillator
    port map(
      oscena => '1',
      clkout => clock_o
      );

end architecture;
