library ieee;
use ieee.std_logic_1164.all;

library nsl_io;

entity ddr_output_tristated is
  port(
    clock_i : in nsl_io.diff.diff_pair;
    d_i : in std_ulogic_vector(1 downto 0);
    oe_i : in std_ulogic;
    pad_o : out nsl_io.io.tristated
    );
end entity;

architecture sim of ddr_output_tristated is

  signal df: std_ulogic;

begin

  ck: process(clock_i.p) is
  begin
    if rising_edge(clock_i.p) then
      pad_o.v <= d_i(0);
      pad_o.en <= oe_i;
      df <= d_i(1);
    end if;

    if falling_edge(clock_i.p) then
      pad_o.v <= df;
    end if;
  end process;

end architecture;
