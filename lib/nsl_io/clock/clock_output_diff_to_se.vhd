library ieee;
use ieee.std_logic_1164.all;

library nsl_io;

entity clock_output_diff_to_se is
  port(
    clock_i  : in nsl_io.diff.diff_pair;
    port_o : out std_ulogic
    );
end entity;

architecture gen of clock_output_diff_to_se is
  
begin

  iod: nsl_io.ddr.ddr_output
    port map(
      clock_i => clock_i,
      d_i => "01",
      dd_o => port_o
      );
  
end architecture;
