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
      user_signal_to_global_buffer:in std_logic;
      global_buffer_output:out std_logic
      );
  end component;

begin

  gb: sb_gb
    port map(
      user_signal_to_global_buffer => clock_i,
      global_buffer_output => clock_o
      );
  
end architecture;
