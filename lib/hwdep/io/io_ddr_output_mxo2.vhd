library ieee;
use ieee.std_logic_1164.all;

library signalling, machxo2;

entity io_ddr_output is
  port(
    p_clk : in signalling.diff.diff_pair;
    p_d   : in std_ulogic_vector(1 downto 0);
    p_dd  : out std_ulogic
    );
end entity;

architecture mxo2 of io_ddr_output is

begin

  pad: machxo2.components.oddrxe
   port map (
      sclk => p_clk.p,
      rst => '0',
      q => p_dd,
      d0 => p_d(0),
      d1 => p_d(1)
   );

end architecture;
