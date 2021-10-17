library ieee;
use ieee.std_logic_1164.all;

library machxo2;

entity clock_buffer is
  generic(
    mode_c : string := "global"
    );
  port(
    clock_i      : in std_ulogic;
    clock_o      : out std_ulogic
    );
end entity;

architecture mxo2 of clock_buffer is

begin

  is_none: if mode_c = "none"
  generate
    clock_o <= clock_i;
  end generate;

  is_not_none: if mode_c /= "none"
  generate
    gb: machxo2.components.eclkbridgecs
      port map(
        clk0 => clock_i,
        clk1 => '0',
        sel => '0',
        ecsout => clock_o
        );
  end generate;

end architecture;
