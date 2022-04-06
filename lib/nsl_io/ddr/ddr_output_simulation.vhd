library ieee;
use ieee.std_logic_1164.all;

library nsl_io;

entity ddr_output is
  port(
    clock_i : in nsl_io.diff.diff_pair;
    d_i   : in std_ulogic_vector(1 downto 0);
    dd_o  : out std_ulogic
    );
end entity;

architecture sim of ddr_output is

  signal df: std_ulogic;
  
begin

  ck: process(clock_i.p) is
  begin
    if rising_edge(clock_i.p) then
      dd_o <= d_i(0);
      df <= d_i(1);
    end if;
    if falling_edge(clock_i.p) then
      dd_o <= df;
    end if;
  end process;
  
end architecture;
