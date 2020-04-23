library ieee;
use ieee.std_logic_1164.all;

library nsl_io;

entity clock_output_se_to_se is
  port(
    clock_i  : in std_ulogic;
    port_o : out std_ulogic
    );
end entity;

architecture gen of clock_output_se_to_se is

  signal clock: nsl_io.diff.diff_pair;
  
begin

  clock.p <= clock_i;
  clock.n <= not clock_i;
  
  iod: nsl_io.ddr.ddr_output
    port map(
      clock_i => clock,
      d_i => "01",
      dd_o => port_o
      );
  
end architecture;
