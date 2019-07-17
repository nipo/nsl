library ieee;
use ieee.std_logic_1164.all;

library unisim;

entity reset_at_startup is
  port(
    p_clk       : in std_ulogic;
    p_resetn    : out std_ulogic
    );
end entity;

architecture xc of reset_at_startup is

  signal reset: std_ulogic;

begin

  xc_roc: unisim.vcomponents.roc
    port map(
      o => reset
      );

  p_resetn <= not reset;
  
end;
