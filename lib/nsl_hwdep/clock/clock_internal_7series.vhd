library ieee;
use ieee.std_logic_1164.all;

entity clock_internal is
  port(
    clock_o      : out std_ulogic
    );
end entity;

architecture seven_series of clock_internal is

  attribute BOX_TYPE : string;

  component STARTUPE2
    generic (
      PROG_USR : string := "FALSE";
      SIM_CCLK_FREQ : real := 0.0
      );
    port (
      CFGCLK : out std_ulogic;
      CFGMCLK : out std_ulogic;
      EOS : out std_ulogic;
      PREQ : out std_ulogic;
      CLK : in std_ulogic;
      GSR : in std_ulogic;
      GTS : in std_ulogic;
      KEYCLEARB : in std_ulogic;
      PACK : in std_ulogic;
      USRCCLKO : in std_ulogic;
      USRCCLKTS : in std_ulogic;
      USRDONEO : in std_ulogic;
      USRDONETS : in std_ulogic
      );
  end component;
  attribute BOX_TYPE of
    STARTUPE2 : component is "PRIMITIVE";

  component BUFG
    port (
      O : out std_ulogic;
      I : in std_ulogic
      );
  end component;
  attribute BOX_TYPE of
    BUFG : component is "PRIMITIVE";

  signal int_clk : std_ulogic;

begin

  inst : startupe2
    port map (
      cfgmclk => int_clk,
      clk => '0',
      gsr => '0',
      gts => '0',
      keyclearb => '1',
      pack => '0',
      usrcclko => '0',
      USRCCLKTS => '0',
      USRDONEO => '1',
      USRDONETS => '0'
      );

  buf_clock: bufg
    port map(
      i => int_clk,
      o => clock_o
      );

end architecture;
