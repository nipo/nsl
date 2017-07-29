library ieee;
use ieee.std_logic_1164.all;

library unisim;
use unisim.vcomponents.all;

entity clock_output is
  port(
    p_clk     : in  std_ulogic;
    p_clk_neg : in  std_ulogic;
    p_port    : out std_ulogic
    );
end entity;

architecture xil of clock_output is
  
begin

  clk50_out: oddr2
    generic map(
      ddr_alignment => "NONE",
      init => '0',
      srtype => "SYNC")
   port map (
      q => p_port,
      c0 => p_clk,
      c1 => p_clk_neg,
      ce => '1',
      d0 => '0',
      d1 => '1',
      r => '0',
      s => '0'
   );

end architecture;
