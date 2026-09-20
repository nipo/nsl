library ieee;
use ieee.std_logic_1164.all;

library nsl_io;

entity pad_diff_io is
  port(
    v_i : in nsl_io.io.tristated;
    v_o : out std_ulogic;
    p_io : inout std_logic;
    n_io : inout std_logic
    );
end entity;

architecture rtl of pad_diff_io is

  attribute BOX_TYPE : string;

  component IOBUFDS
    generic (
      CAPACITANCE : string := "DONT_CARE";
      DIFF_TERM : boolean := false;
      IBUF_DELAY_VALUE : string := "0";
      IBUF_LOW_PWR : boolean := true;
      IFD_DELAY_VALUE : string := "AUTO";
      IOSTANDARD : string := "DEFAULT";
      SLEW : string := "SLOW"
      );
    port (
      O : out std_ulogic;
      IO : inout std_logic;
      IOB : inout std_logic;
      I : in std_ulogic;
      T : in std_ulogic
      );
  end component;
  attribute BOX_TYPE of
    IOBUFDS : component is "PRIMITIVE";

  signal off_s: std_ulogic;

begin

  off_s <= not v_i.en;

  driver: iobufds
    port map(
      o => v_o,
      io => p_io,
      iob => n_io,
      i => v_i.v,
      t => off_s
      );

end architecture;
