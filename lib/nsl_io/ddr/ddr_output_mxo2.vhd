library ieee;
use ieee.std_logic_1164.all;

library nsl_io;

entity ddr_output is
  port(
    clock_i : in nsl_io.diff.diff_pair;
    d_i   : in std_ulogic_vector(1 downto 0);
    dd_o  : out std_ulogic
    );
end entity;

architecture mxo2 of ddr_output is

begin

  pad: machxo2.components.oddrxe
   port map (
      sclk => clock_i.p,
      rst => '0',
      q => dd_o,
      d0 => d_i(0),
      d1 => d_i(1)
   );

end architecture;
