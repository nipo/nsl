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

architecture xil of ddr_input is

  attribute BOX_TYPE : string;

  component IDDR2
    generic (
      DDR_ALIGNMENT : string := "NONE";
      INIT_Q0 : bit := '0';
      INIT_Q1 : bit := '0';
      SRTYPE : string := "SYNC"
      );
    port (
      Q0 : out std_ulogic;
      Q1 : out std_ulogic;
      C0 : in std_ulogic;
      C1 : in std_ulogic;
      CE : in std_ulogic := 'H';
      D : in std_ulogic;
      R : in std_ulogic := 'L';
      S : in std_ulogic := 'L'
      );
  end component;
  attribute BOX_TYPE of
    IDDR2 : component is "PRIMITIVE";
  
begin

  no_inv: if not invert_clock_polarity_c
  generate
    pad: iddr2
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
    pad: iddr2
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
