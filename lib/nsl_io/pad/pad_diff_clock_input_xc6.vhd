library ieee;
use ieee.std_logic_1164.all;

library unisim;
library nsl_io;

entity pad_diff_clock_input is
  generic(
    diff_term : boolean := true;
    invert    : boolean := false
    );
  port(
    p_pad : in  nsl_io.diff.diff_pair;
    p_clk : out nsl_io.diff.diff_pair
    );
end entity;

architecture sp6 of pad_diff_clock_input is

begin

  inv: if invert
  generate
    inst_inv: unisim.vcomponents.ibufgds_diff_out
      generic map(
        diff_term => diff_term
        )
      port map (
        i => p_pad.p,
        ib => p_pad.n,
        o => p_clk.n,
        ob => p_clk.p
        );
  end generate;

  noinv: if not invert
  generate
    inst_fw: unisim.vcomponents.ibufgds_diff_out
      generic map(
        diff_term => diff_term
        )
      port map (
        i => p_pad.p,
        ib => p_pad.n,
        o => p_clk.p,
        ob => p_clk.n
        );
  end generate;

end architecture;
