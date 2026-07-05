library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_io;
use nsl_io.diff.all;

entity pad_tmds_input is
  generic(
    invert_c : boolean := false
    );
  port(
    data_o : out std_ulogic;
    pad_i : in diff_pair
    );
end entity;

architecture rtl of pad_tmds_input is

  attribute BOX_TYPE : string;

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

  signal data_s: std_ulogic;
  
begin

  se2diff: ibufds
    generic map(
      diff_term => false,
      iostandard => "TMDS_33"
      )
    port map(
      o => data_s,
      i => pad_i.p,
      ib => pad_i.n
      );
  
  data_o <= (not data_s) when invert_c else data_s;

end architecture;
