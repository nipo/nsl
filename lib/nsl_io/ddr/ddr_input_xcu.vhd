library ieee;
use ieee.std_logic_1164.all;

library nsl_io;

-- UltraScale / UltraScale+ DDR input, same behavior as the 7-series IDDR
-- in SAME_EDGE mode. CB is the same clock, inverted inside the primitive.
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

architecture xcu of ddr_input is

  attribute BOX_TYPE : string;

  component IDDRE1
    generic (
      DDR_CLK_EDGE : string := "OPPOSITE_EDGE";
      IS_CB_INVERTED : bit := '0';
      IS_C_INVERTED : bit := '0'
      );
    port (
      Q1 : out std_ulogic;
      Q2 : out std_ulogic;
      C : in std_ulogic;
      CB : in std_ulogic;
      D : in std_ulogic;
      R : in std_ulogic
      );
  end component;
  attribute BOX_TYPE of
    IDDRE1 : component is "PRIMITIVE";

  signal clock_s : std_ulogic;

begin

  clock_s <= clock_i.n when invert_clock_polarity_c else clock_i.p;

  pad: iddre1
    generic map(
      ddr_clk_edge => "SAME_EDGE",
      is_cb_inverted => '1'
      )
    port map(
      d => dd_i,
      c => clock_s,
      cb => clock_s,
      q1 => d_o(1),
      q2 => d_o(0),
      r => '0'
      );

end architecture;
