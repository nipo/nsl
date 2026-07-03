library ieee;
use ieee.std_logic_1164.all;

entity clock_buffer is
  port(
    clock_i      : in std_ulogic;
    clock_o      : out std_ulogic
    );
end entity;

architecture ecp5 of clock_buffer is

  COMPONENT ECLKBRIDGECS
    PORT (CLK0 :IN STD_LOGIC;
          CLK1 :IN STD_LOGIC;
          SEL :IN STD_LOGIC;
          ECSOUT :OUT STD_LOGIC);
  END COMPONENT;

begin

  gb: eclkbridgecs
    port map(
      clk0 => clock_i,
      clk1 => '0',
      sel => '0',
      ecsout => clock_o
      );

end architecture;
