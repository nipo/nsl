library ieee;
use ieee.std_logic_1164.all;

library unisim;

entity clock_internal is
  port(
    clock_o      : out std_ulogic
    );
end entity;

architecture sp6 of clock_internal is

  signal int_clk : std_ulogic;

  attribute period: string;
  attribute period of int_clk : signal is "16 ns";
  
begin

  inst : unisim.vcomponents.startup_spartan6
   port map (
     cfgmclk => int_clk,
     clk => '0',
     gsr => '0',
     gts => '0',
     keyclearb => '0'
   );

  buf_clock: unisim.vcomponents.bufg
    port map(
      i => int_clk,
      o => clock_o
      );

end architecture;
