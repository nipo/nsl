library ieee;
use ieee.std_logic_1164.all;

library unisim;
use unisim.vcomponents.all;

library signalling;

entity io_ddr_output is
  port(
    p_clk : in signalling.diff.diff_pair;
    p_d   : in std_ulogic_vector(1 downto 0);
    p_dd  : out std_ulogic
    );
end entity;

architecture xil of io_ddr_output is

begin

  pad: oddr2
    generic map(
      ddr_alignment => "C0",
      init => '0',
      srtype => "SYNC")
   port map (
      q => p_dd,
      c0 => p_clk.p,
      c1 => p_clk.n,
      ce => '1',
      -- Yes, they are inverted.
      d0 => p_d(0),
      d1 => p_d(1),
      r => '0',
      s => '0'
   );

end architecture;
