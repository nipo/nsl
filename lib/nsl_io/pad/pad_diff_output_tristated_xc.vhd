library ieee;
use ieee.std_logic_1164.all;

library nsl_io;
use nsl_io.diff.all;

entity pad_diff_output_tristated is
  port(
    p_se : in nsl_io.io.tristated;
    p_diff : out diff_pair
    );
end entity;

architecture rtl of pad_diff_output_tristated is

  attribute BOX_TYPE : string;

  component OBUFTDS
    generic (
      CAPACITANCE : string := "DONT_CARE";
      IOSTANDARD : string := "DEFAULT";
      SLEW : string := "SLOW"
      );
    port (
      O : out std_ulogic;
      OB : out std_ulogic;
      I : in std_ulogic;
      T : in std_ulogic
      );
  end component;
  attribute BOX_TYPE of
    OBUFTDS : component is "PRIMITIVE";

  signal off_s: std_ulogic;

begin

  off_s <= not p_se.en;

  se2diff: obuftds
    port map(
      o => p_diff.p,
      ob => p_diff.n,
      i => p_se.v,
      t => off_s
      );

end architecture;
