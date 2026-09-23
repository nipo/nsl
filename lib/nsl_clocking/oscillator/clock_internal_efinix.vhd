library ieee;
use ieee.std_logic_1164.all;

entity clock_internal is
  port(
    clock_o      : out std_ulogic
    );
end entity;

architecture efinix of clock_internal is

  signal int_clk : std_ulogic;

  component osc is
    port(
      clkout : out std_ulogic
      );
  end component;
  
begin

  gen: osc
    port map(
      clkout => clock_o
      );
  
end architecture;
