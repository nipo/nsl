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

architecture ecp5 of clock_buffer is

  component ECLKBUF
    port (
      I : in  std_logic;
      O : out std_logic
      );
  end component;

begin

  is_none: if mode_c = "none"
  generate
    clock_o <= clock_i;
  end generate;

  is_not_none: if mode_c /= "none"
  generate
    clock_o <= clock_i;
--    gb: eclkbuf
--      port map(
--        i => clock_i,
--        o => clock_o
--        );
  end generate;

end architecture;
