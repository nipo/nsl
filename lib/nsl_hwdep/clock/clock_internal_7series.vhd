library ieee;
use ieee.std_logic_1164.all;

library unisim;
use unisim.vcomponents.all;

entity clock_internal is
  port(
    clock_o      : out std_ulogic
    );
end entity;

architecture seven_series of clock_internal is
  
begin

  inst : startupe2
    port map (
      cfgmclk => clock_o,
      clk => '0',
      gsr => '0',
      gts => '0',
      keyclearb => '0',
      pack => '0',
      usrcclko => '0',
      USRCCLKTS => '0',
      USRDONEO => '0',
      USRDONETS => '0'
      );

end architecture;