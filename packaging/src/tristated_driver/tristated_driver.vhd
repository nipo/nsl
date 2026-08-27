library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library unisim;
use unisim.vcomponents.bufio;

entity tristated_driver is
  generic(
    count : positive
    );
  port(
    tristated_o: out std_logic_vector(count-1 downto 0);
    tristated_oe: in std_logic_vector(count-1 downto 0) := (others => '0');
    tristated_i: in std_logic_vector(count-1 downto 0) := (others => '0');

    io: inout std_logic_vector(count-1 downto 0)
    );
end entity;

architecture rtl of tristated_driver is

  attribute X_INTERFACE_INFO : string;
  attribute X_INTERFACE_PARAMETER : string;
  attribute X_INTERFACE_MODE : string;

  attribute X_INTERFACE_MODE of tristated_i : signal is "SLAVE";
  attribute X_INTERFACE_INFO of tristated_i : signal is "nsl:io:tristated:1.0 tristated o";
  attribute X_INTERFACE_INFO of tristated_o : signal is "nsl:io:tristated:1.0 tristated i";
  attribute X_INTERFACE_INFO of tristated_oe: signal is "nsl:io:tristated:1.0 tristated oe";

  signal t: std_logic_vector(count-1 downto 0);
  
begin

  t <= not tristated_oe;

  gates: for i in tristated_i'range
  generate
    buf: bufio
      port map(
        i => tristated_i(i),
        o => tristated_o(i),
        t => t(i),
        io => io(i)
        );
  end generate;

end;
