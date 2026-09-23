library ieee;
use ieee.std_logic_1164.all;

entity clock_internal is
  port(
    clock_o      : out std_ulogic
    );
end entity;

architecture sp6 of clock_internal is

  attribute BOX_TYPE : string;

  component STARTUP_SPARTAN6
    port (
      CFGCLK : out std_ulogic;
      CFGMCLK : out std_ulogic;
      EOS : out std_ulogic;
      CLK : in std_ulogic;
      GSR : in std_ulogic;
      GTS : in std_ulogic;
      KEYCLEARB : in std_ulogic
      );
  end component;
  attribute BOX_TYPE of
    STARTUP_SPARTAN6 : component is "PRIMITIVE";

  component BUFG
    port (
      O : out std_ulogic;
      I : in std_ulogic
      );
  end component;
  attribute BOX_TYPE of
    BUFG : component is "PRIMITIVE";

  signal int_clk : std_ulogic;

  attribute period: string;
  attribute period of int_clk : signal is "16 ns";
  
begin

  inst : startup_spartan6
   port map (
     cfgmclk => int_clk,
     clk => '0',
     gsr => '0',
     gts => '0',
     keyclearb => '0'
   );

  buf_clock: bufg
    port map(
      i => int_clk,
      o => clock_o
      );

end architecture;
