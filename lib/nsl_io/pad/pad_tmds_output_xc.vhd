library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_io;
use nsl_io.diff.all;

entity pad_tmds_output is
  generic(
    invert_c : boolean := false;
    driver_mode_c : string := "default"
    );
  port(
    data_i : in std_ulogic;
    pad_o : out diff_pair
    );
end entity;

architecture rtl of pad_tmds_output is

  attribute BOX_TYPE : string;

  component OBUFDS
    generic (
      CAPACITANCE : string := "DONT_CARE";
      IOSTANDARD : string := "DEFAULT";
      SLEW : string := "SLOW"
      );
    port (
      O : out std_ulogic;
      OB : out std_ulogic;
      I : in std_ulogic
      );
  end component;
  attribute BOX_TYPE of
    OBUFDS : component is "PRIMITIVE";

  signal data_s : std_ulogic;
  
begin

  data_s <= (not data_i) when invert_c else data_i;
  
  se2diff: obufds
    generic map(
      iostandard => "TMDS_33"
      )
    port map(
      o => pad_o.p,
      ob => pad_o.n,
      i => data_s
      );
  
end architecture;
