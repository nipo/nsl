library ieee;
use ieee.std_logic_1164.all;

library machxo2;

entity clock_buffer is
  port(
    clock_i      : in std_ulogic;
    clock_o      : out std_ulogic
    );
end entity;

architecture mxo2 of clock_buffer is

begin

  gb: machxo2.components.eclkbridgecs
    port map(
      clk0 => clock_i,
      clk1 => '0',
      sel => '0',
      ecsout => clock_o
      );

end architecture;
