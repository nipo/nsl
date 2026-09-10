library ieee;
use ieee.std_logic_1164.all;

entity clock_buffer is
  generic(
    mode_c : string := "global"
    );
  port(
    clock_i      : in std_ulogic;
    clock_o      : out std_ulogic
    );
end entity;

-- nextpnr promotes clock nets to global buffers on its own, no
-- explicit SB_GB instance is needed.
architecture ice of clock_buffer is

begin

  clock_o <= clock_i;

end architecture;
