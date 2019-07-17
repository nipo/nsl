library ieee;
use ieee.std_logic_1164.all;

library machxo2;

entity reset_at_startup is
  port(
    p_clk       : in std_ulogic;
    p_resetn    : out std_ulogic
    );
end entity;

architecture mxo2 of reset_at_startup is

begin

  mxo2_roc: machxo2.components.fd1p3ax
    generic map(
      gsr => "ENABLED"
      )
    port map(
      d => '1',
      q => p_resetn,
      sp => '1',
      ck => p_clk
      );
  
end;
