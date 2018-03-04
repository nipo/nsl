library ieee;
use ieee.std_logic_1164.all;

library hwdep;

entity clock_output is
  port(
    p_clk     : in  std_ulogic;
    p_clk_neg : in  std_ulogic;
    p_port    : out std_ulogic
    );
end entity;

architecture gen of clock_output is
  
begin

  iod: hwdep.io.io_ddr_output
    port map(
      p_clk => p_clk,
      p_d => "01",
      p_dd => p_port
      );
  
end architecture;
