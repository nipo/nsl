library ieee;
use ieee.std_logic_1164.all;

entity clock_buffer is
  port(
    clock_i      : in std_ulogic;
    clock_o      : out std_ulogic
    );
end entity;

architecture ice of clock_buffer is

  component SB_GB
    port (
      USER_SIGNAL_TO_GLOBAL_BUFFER:in std_logic;
      GLOBAL_BUFFER_OUTPUT:out std_logic
      );
  end component;

begin

  gb: sb_gb
    port map(
      USER_SIGNAL_TO_GLOBAL_BUFFER => clock_i,
      GLOBAL_BUFFER_OUTPUT => clock_o
      );

end architecture;
