library ieee;
use ieee.std_logic_1164.all;

library machxo2;

entity reset_at_startup is
  port(
    clock_i       : in std_ulogic;
    reset_n_o    : out std_ulogic
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
      q => reset_n_o,
      sp => '1',
      ck => clock_i
      );
  
end;
