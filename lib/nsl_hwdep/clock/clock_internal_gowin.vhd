library ieee;
use ieee.std_logic_1164.all;

entity clock_internal is
  port(
    clock_o      : out std_ulogic
    );
end entity;

architecture gw of clock_internal is

  component osch
    generic (
      freq_div: in integer := 96
    );
    port (
      oscout: out std_logic
    );
  end component;

begin

  osc_inst: osch
    generic map (
      freq_div => 4
    )
    port map (
      oscout => clock_o
    );

end architecture;
