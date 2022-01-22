library ieee;
use ieee.std_logic_1164.all;

library nsl_io, unisim;

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

architecture xil of ddr_input is
  
begin

  no_inv: if not invert_clock_polarity_c
  generate
    pad: unisim.vcomponents.iddr2
      generic map(
        ddr_alignment => "C0",
        srtype => "SYNC")
      port map (
        d => dd_i,
        c0 => clock_i.p,
        c1 => clock_i.n,
        ce => '1',
        q0 => d_o(1),
        q1 => d_o(0),
        r => '0',
        s => '0'
        );
  end generate;

  inv: if invert_clock_polarity_c
  generate
    pad: unisim.vcomponents.iddr2
      generic map(
        ddr_alignment => "C0",
        srtype => "SYNC")
      port map (
        d => dd_i,
        c0 => clock_i.n,
        c1 => clock_i.p,
        ce => '1',
        q0 => d_o(1),
        q1 => d_o(0),
        r => '0',
        s => '0'
        );
  end generate;
    
end architecture;
