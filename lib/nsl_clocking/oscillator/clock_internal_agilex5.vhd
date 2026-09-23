library ieee;
use ieee.std_logic_1164.all;

-- Agilex 5 internal oscillator, the one the SDM runs from.  The data
-- sheet publishes no rate for it on the fabric side.
entity clock_internal is
  port(
    clock_o      : out std_ulogic
    );
end entity;

architecture agilex5 of clock_internal is

  component tennm_sdm_oscillator is
    port(
      clkout : out std_logic;
      clkout1 : out std_logic
      );
  end component;

begin

  gen: tennm_sdm_oscillator
    port map(
      clkout => clock_o,
      clkout1 => open
      );

end architecture;
