library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_io;
use nsl_io.diff.all;

entity pad_diff_output is
  generic(
    is_clock : boolean := false
    );
  port(
    p_se : in std_ulogic;
    p_diff : out diff_pair
    );
end entity;

architecture rtl of pad_diff_output is

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
  
begin

  se2diff: obufds
    port map(
      o => p_diff.p,
      ob => p_diff.n,
      i => p_se
      );
  
end architecture;
