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

architecture sim of clock_buffer is
begin

  clock_o <= clock_i;

end architecture;
