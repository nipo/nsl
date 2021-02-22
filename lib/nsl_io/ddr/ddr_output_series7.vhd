library ieee;
use ieee.std_logic_1164.all;

library nsl_io, unisim;

entity ddr_output is
  port(
    clock_i : in nsl_io.diff.diff_pair;
    d_i   : in std_ulogic_vector(1 downto 0);
    dd_o  : out std_ulogic
    );
end entity;

architecture series7 of ddr_output is

begin

  pad: unisim.vcomponents.oddr
    generic map(
      ddr_clk_edge => "SAME_EDGE",
      init => '0',
      srtype => "ASYNC")
   port map (
      q => dd_o,
      c => clock_i.p,
      ce => '1',
      d1 => d_i(0),
      d2 => d_i(1),
      r => '0',
      s => '0'
   );

end architecture;
