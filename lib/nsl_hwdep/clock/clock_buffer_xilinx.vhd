library ieee;
use ieee.std_logic_1164.all;

library unisim;
use unisim.vcomponents.all;

entity clock_buffer is
  port(
    clock_i      : in std_ulogic;
    clock_o      : out std_ulogic
    );
end entity;

architecture xil of clock_buffer is
begin

  buf: unisim.vcomponents.bufg
    port map(
      i => clock_i,
      o => clock_o
      );

end architecture;
