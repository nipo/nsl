library ieee;
use ieee.std_logic_1164.all;

library unisim;
use unisim.vcomponents.all;

library signalling;

entity io_ddr_input is
  port(
    p_clk : in signalling.diff.diff_pair;
    p_dd  : in std_ulogic;
    p_d   : out std_ulogic_vector(1 downto 0)
    );
end entity;

architecture xil of io_ddr_input is
  
begin

  pad: iddr2
    generic map(
      ddr_alignment => "C1",
      srtype => "SYNC")
   port map (
      d => p_dd,
      c0 => p_clk.p,
      c1 => p_clk.n,
      ce => '1',
      q0 => p_d(1),
      q1 => p_d(0),
      r => '0',
      s => '0'
   );

end architecture;
