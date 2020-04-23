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

architecture xil of ddr_output is

begin

  pad: unisim.vcomponents.oddr2
    generic map(
      ddr_alignment => "C0",
      init => '0',
      srtype => "SYNC")
   port map (
      q => dd_o,
      c0 => clock_i.p,
      c1 => clock_i.n,
      ce => '1',
      d0 => d_i(0),
      d1 => d_i(1),
      r => '0',
      s => '0'
   );

end architecture;
