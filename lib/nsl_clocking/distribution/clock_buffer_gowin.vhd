library ieee;
use ieee.std_logic_1164.all;

library unisim;
use unisim.vcomponents.all;

entity clock_buffer is
  generic(
    mode_c : string := "global"
    );
  port(
    clock_i      : in std_ulogic;
    clock_o      : out std_ulogic
    );
end entity;

architecture gowin of clock_buffer is

  COMPONENT BUFG
    PORT(
      O:OUT std_logic;
      I:IN std_logic
      );
  END COMPONENT;
  
begin

  is_none: if mode_c = "none"
  generate
    clock_o <= clock_i;
  end generate;

  is_bufg: if mode_c /= "none"
  generate
    buf: bufg
      port map(
        i => clock_i,
        o => clock_o
        );
  end generate;

end architecture;
