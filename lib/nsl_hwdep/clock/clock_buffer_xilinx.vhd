library ieee;
use ieee.std_logic_1164.all;

entity clock_buffer is
  port(
    clock_i      : in std_ulogic;
    clock_o      : out std_ulogic
    );
end entity;

architecture xil of clock_buffer is

  attribute BOX_TYPE : string;

  component BUFG
    port (
      O : out std_ulogic;
      I : in std_ulogic
      );
  end component;
  attribute BOX_TYPE of
    BUFG : component is "PRIMITIVE";

begin

  buf: bufg
    port map(
      i => clock_i,
      o => clock_o
      );

end architecture;
