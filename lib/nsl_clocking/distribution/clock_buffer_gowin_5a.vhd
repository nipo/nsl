library ieee;
use ieee.std_logic_1164.all;

entity clock_buffer is
  generic(
    mode_c : string := "global"
    );
  port(
    clock_i      : in std_ulogic;
    clock_o      : out std_ulogic
    );
end entity;

architecture gw1n of clock_buffer is
  
  component dce is
    port (
      clkin : in std_logic;
      ce : in std_logic;
      clkout : out std_logic
      );
  end component;

  component dhce is
    port (
      clkin : in std_logic;
      cen : in std_logic;
      clkout : out std_logic
      );
  end component;

begin

  is_none: if mode_c = "none"
  generate
    clock_o <= clock_i;
  end generate;

  is_hclk: if mode_c = "hclk"
  generate
    buf: dhce
      port map(
        clkin => clock_i,
        cen => '1',
        clkout => clock_o
        );
  end generate;

  is_global: if mode_c /= "none" and mode_c /= "hclk"
  generate
    buf: dce
      port map(
        clkin => clock_i,
        ce => '1',
        clkout => clock_o
        );
  end generate;

end architecture;
