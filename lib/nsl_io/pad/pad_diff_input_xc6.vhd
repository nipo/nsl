library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_io;
use nsl_io.diff.all;

entity pad_diff_input is
  generic(
    diff_term : boolean := true;
    is_clock  : boolean := false;
    invert    : boolean := false
    );
  port(
    p_diff : in diff_pair;
    p_se   : out std_ulogic
    );
end entity;

architecture rtl of pad_diff_input is

  attribute BOX_TYPE : string;

  component IBUFGDS
    generic (
      CAPACITANCE : string := "DONT_CARE";
      DIFF_TERM : boolean := FALSE;
      IBUF_DELAY_VALUE : string := "0";
      IBUF_LOW_PWR : boolean := TRUE;
      IOSTANDARD : string := "DEFAULT"
      );
    port (
      O : out std_ulogic;
      I : in std_ulogic;
      IB : in std_ulogic
      );
  end component;
  attribute BOX_TYPE of
    IBUFGDS : component is "PRIMITIVE";

  component IBUFDS
    generic (
      CAPACITANCE : string := "DONT_CARE";
      DIFF_TERM : boolean := FALSE;
      DQS_BIAS : string := "FALSE";
      IBUF_DELAY_VALUE : string := "0";
      IBUF_LOW_PWR : boolean := TRUE;
      IFD_DELAY_VALUE : string := "AUTO";
      IOSTANDARD : string := "DEFAULT"
      );
    port (
      O : out std_ulogic;
      I : in std_ulogic;
      IB : in std_ulogic
      );
  end component;
  attribute BOX_TYPE of
    IBUFDS : component is "PRIMITIVE";

  signal s_se : std_ulogic;
  
begin

  if_clk: if is_clock generate
    diff_clk_input : ibufgds
      generic map (
        diff_term => diff_term
        )
      port map(
        i  => p_diff.p,
        ib => p_diff.n,
        o  => s_se
        );

  end generate;

  if_io: if (not is_clock) generate
    diff_input : ibufds
      generic map (
        diff_term => diff_term
        )
      port map(
        i  => p_diff.p,
        ib => p_diff.n,
        o  => s_se
        );

  end generate;
    
  p_se <= s_se when not invert else (not s_se);
  
end architecture;
