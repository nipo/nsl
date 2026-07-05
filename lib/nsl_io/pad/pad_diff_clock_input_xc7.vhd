library ieee;
use ieee.std_logic_1164.all;

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

  attribute BOX_TYPE : string;
  component IBUFGDS_DIFF_OUT
    generic (
      DIFF_TERM : boolean := FALSE;
      IBUF_LOW_PWR : boolean := TRUE;
      IOSTANDARD : string := "DEFAULT"
      );
    port (
      O : out STD_ULOGIC;
      OB : out STD_ULOGIC;
      I : in STD_ULOGIC;
      IB : in STD_ULOGIC
      );
  end component;
  attribute BOX_TYPE of
    IBUFGDS_DIFF_OUT : component is "PRIMITIVE";

begin

  inv: if invert
  generate
    inst_inv: ibufgds_diff_out
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
    inst_fw: ibufgds_diff_out
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
