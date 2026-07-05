library ieee;
use ieee.std_logic_1164.all;

library nsl_io;

entity clock_input_diff_to_diff is
  generic(
    diff_term : boolean := true;
    invert    : boolean := false
    );
  port(
    pad_i : in  nsl_io.diff.diff_pair;
    clock_o : out nsl_io.diff.diff_pair
    );
end entity;

architecture sp6 of clock_input_diff_to_diff is

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
        i => pad_i.p,
        ib => pad_i.n,
        o => clock_o.n,
        ob => clock_o.p
        );
  end generate;

  noinv: if not invert
  generate
    inst_fw: ibufgds_diff_out
      generic map(
        diff_term => diff_term
        )
      port map (
        i => pad_i.p,
        ib => pad_i.n,
        o => clock_o.p,
        ob => clock_o.n
        );
  end generate;

end architecture;
