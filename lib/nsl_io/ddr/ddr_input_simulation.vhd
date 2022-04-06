library ieee;
use ieee.std_logic_1164.all;

library nsl_io;

entity ddr_input is
  generic(
    invert_clock_polarity_c : boolean := false
    );
  port(
    clock_i : in nsl_io.diff.diff_pair;
    dd_i  : in std_ulogic;
    d_o   : out std_ulogic_vector(1 downto 0)
    );
end entity;

architecture sim of ddr_input is

begin

  f0r1: if not invert_clock_polarity_c
  generate
    signal df: std_ulogic;
    signal d: std_ulogic_vector(1 downto 0);
  begin
    ck: process(clock_i.p) is
    begin
      if falling_edge(clock_i.p) then
        df <= dd_i;
      end if;
      if rising_edge(clock_i.p) then
        d(1) <= dd_i;
        d(0) <= df;
        d_o <= d;
      end if;
    end process;
  end generate;

  r0f1rs: if invert_clock_polarity_c
  generate
    signal dr: std_ulogic;
    signal d: std_ulogic_vector(1 downto 0);
  begin
    ck: process(clock_i.p) is
    begin
      if rising_edge(clock_i.p) then
        dr <= dd_i;
      end if;
      if falling_edge(clock_i.p) then
        d(1) <= dd_i;
        d(0) <= dr;
      end if;
      if rising_edge(clock_i.p) then
        d_o <= d;
      end if;
    end process;
  end generate;

end architecture;
