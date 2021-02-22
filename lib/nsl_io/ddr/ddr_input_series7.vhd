library ieee;
use ieee.std_logic_1164.all;

library nsl_io, unisim;

entity ddr_input is
  port(
    clock_i : in nsl_io.diff.diff_pair;
    dd_i  : in std_ulogic;
    d_o   : out std_ulogic_vector(1 downto 0)
    );
end entity;

architecture series7 of ddr_input is
  
begin

  pad: unisim.vcomponents.iddr
    generic map(
      ddr_clk_edge => "SAME_EDGE_PIPELINED"
      )
   port map (
      d => dd_i,
      c => clock_i.p,
      ce => '1',
      q1 => d_o(0),
      q2 => d_o(1),
      r => '0',
      s => '0'
   );

end architecture;
