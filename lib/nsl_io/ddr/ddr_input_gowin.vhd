library ieee;
use ieee.std_logic_1164.all;

library nsl_io, gowin;

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

architecture gw1n of ddr_input is

  signal clock_s: std_ulogic;

begin

  -- Gowin IDDR gate behavior:
  --              ____      ____      ____      ____      ____
  --  Clock  ____/    \____/    \____/    \____/    \____/    \_
  --  D        A  X B  X C  X D  X E  X F  X ...
  --  Q0_oreg     X    A    X    C    X    E   X ...               | Internal
  --  Q1_oreg          X    B    X    D    X    F   X              | registers
  --  Q0                    X    A    X    C    X    E   X ...
  --  Q1                    X    B    X    D    X    F   X

  -- This is opposed to the clocking scheme defined in the library. Use
  -- inverted clock when no inversion is required.

  no_inv: if invert_clock_polarity_c
  generate
    clock_s <= clock_i.p;
  end generate;

  inv: if not invert_clock_polarity_c
  generate
    clock_s <= clock_i.n;
  end generate;
  
  inst: gowin.components.iddr
    port map (
      d => dd_i,
      clk => clock_s,
      q0 => d_o(0),
      q1 => d_o(1)
      );

end architecture;
