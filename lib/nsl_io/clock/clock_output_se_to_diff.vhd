library ieee;
use ieee.std_logic_1164.all;

library nsl_io;

entity clock_output_se_to_diff is
  port(
    clock_i  : in std_ulogic;
    pin_o : out nsl_io.diff.diff_pair
    );
end entity;

architecture gen of clock_output_se_to_diff is

  signal clock: nsl_io.diff.diff_pair;
  
begin

  clock.p <= clock_i;
  clock.n <= not clock_i;
  
  iop: nsl_io.ddr.ddr_output
    port map(
      clock_i => clock,
      d_i => "01",
      dd_o => pin_o.p
      );

  ion: nsl_io.ddr.ddr_output
    port map(
      clock_i => clock,
      d_i => "10",
      dd_o => pin_o.n
      );
  
end architecture;
