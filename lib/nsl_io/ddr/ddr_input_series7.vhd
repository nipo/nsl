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

architecture series7 of ddr_input is

  attribute BOX_TYPE : string;

  component IDDR
    generic (
      DDR_CLK_EDGE : string := "OPPOSITE_EDGE";
      INIT_Q1 : bit := '0';
      INIT_Q2 : bit := '0';
      SRTYPE : string := "SYNC"
      );
    port (
      Q1 : out std_ulogic;
      Q2 : out std_ulogic;
      C : in std_ulogic;
      CE : in std_ulogic;
      D : in std_ulogic;
      R : in std_ulogic := 'L';
      S : in std_ulogic := 'L'
      );
  end component;
  attribute BOX_TYPE of
    IDDR : component is "PRIMITIVE";
  
begin

  no_inv: if not invert_clock_polarity_c
  generate
    pad: iddr
      generic map(
        ddr_clk_edge => "SAME_EDGE"
        )
      port map (
        d => dd_i,
        c => clock_i.p,
        ce => '1',
        q1 => d_o(1),
        q2 => d_o(0),
        r => '0',
        s => '0'
        );
  end generate;

  inv: if invert_clock_polarity_c
  generate
    pad: iddr
      generic map(
        ddr_clk_edge => "SAME_EDGE"
        )
      port map (
        d => dd_i,
        c => clock_i.n,
        ce => '1',
        q1 => d_o(1),
        q2 => d_o(0),
        r => '0',
        s => '0'
        );
  end generate;

end architecture;
