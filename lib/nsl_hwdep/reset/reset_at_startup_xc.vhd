library ieee;
use ieee.std_logic_1164.all;

library unisim;

entity reset_at_startup is
  port(
    clock_i       : in std_ulogic;
    reset_n_o    : out std_ulogic
    );
end entity;

architecture xc of reset_at_startup is

  signal reset: std_ulogic;

begin

  xc_roc: unisim.vcomponents.roc
    port map(
      o => reset
      );

  reset_n_o <= not reset;
  
end;
