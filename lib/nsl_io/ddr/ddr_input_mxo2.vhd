library ieee;
use ieee.std_logic_1164.all;

library nsl_io, machxo2;

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

architecture mxo2 of ddr_input is
  
begin

  -- Specification for our library:
  --
  -- DDR input
  -- p_clk is sampling clock
  -- p_d(0) is synchronous to p_clk high (on wire first), to be sampled on falling edge
  -- p_d(1) is synchronous to p_clk low (on wire late), to be sampled on rising edge
  --
  --  Sample in design             d0/d1     d2/d3     d4/d5
  --                                 v         v         v
  --              ____      ____      ____      ____      __
  --  Clock  ____/    \____/    \____/    \____/    \____/ 
  --  dd         X D0 X D1 X D2 X D3 X D4 X D5 X
  --  d(0)                  XXXXXX D0 XXXXXX D2 XXXXXX D4 XXXXX
  --  d(1)                  XXXXXX D1 XXXXXX D3 XXXXXX D5 XXXXX



  -- Actual spec from iddrxe
  --              ____      ____      ____      ____      __
  --  sclk   ____/    \____/    \____/    \____/    \____/ 
  --  d          X D0 X D1 X D2 X D3 X D4 X D5 X
  --  qp0        X         X   D1    X   D3    X  D5               Internal stage
  --  qn0             X   D0    X   D2    X   D4    X              Internal stage
  --  q0         X         X         X   D1    X   D3    X  D5
  --  q1         X         X   D0    X   D2    X   D4    X

  -- So we use negated clock as sclk:
  --         ____      ____      ____      ____      ____   
  --  sclk       \____/    \____/    \____/    \____/    \__
  --  d          X D0 X D1 X D2 X D3 X D4 X D5 X
  --  qp0             X   D0    X   D2    X   D4    X              Internal stage
  --  qn0        X         X   D1    X   D2    X  D3    X          Internal stage
  --  q0              X         X   D0    X   D2    X  D4    X
  --  q1              X         X   D1    X   D3    X  D5    X
  --
  --  And finally manage to implement specified lib interface:
  --
  --  Sample in design             d0/d1     d2/d3     d4/d5
  --                                 v         v         v
  --              ____      ____      ____      ____      __
  --  Clock  ____/    \____/    \____/    \____/    \____/ 
  --  dd         X D0 X D1 X D2 X D3 X D4 X D5 X
  --  d(0)                  xxxxXx D0 xxxxXx D2 xxxxXx D4 xxxXx   x == not actually
  --  d(1)                  xxxxXx D1 xxxxXx D3 xxxxXx D5 xxxXx   unstable.

  no_inv: if not invert_clock_polarity_c
  generate
    pad: machxo2.components.iddrxe
      port map (
        d => dd_i,
        rst => '0',
        sclk => clock_i.n,
        q0 => d_o(0),
        q1 => d_o(1)
        );
  end generate;

  inv: if invert_clock_polarity_c
  generate
    pad: machxo2.components.iddrxe
      port map (
        d => dd_i,
        rst => '0',
        sclk => clock_i.p,
        q0 => d_o(0),
        q1 => d_o(1)
        );
  end generate;
  
end architecture;
