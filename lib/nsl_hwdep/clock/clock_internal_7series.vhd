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

  signal int_clk : std_ulogic;

begin

  inst : startupe2
    port map (
      cfgmclk => int_clk,
      clk => '0',
      gsr => '0',
      gts => '0',
      keyclearb => '1',
      pack => '0',
      usrcclko => '0',
      USRCCLKTS => '0',
      USRDONEO => '1',
      USRDONETS => '0'
      );

  buf_clock: unisim.vcomponents.bufg
    port map(
      i => int_clk,
      o => clock_o
      );

end architecture;
