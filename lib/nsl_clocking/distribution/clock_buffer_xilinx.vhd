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

architecture xil of clock_buffer is

  attribute BOX_TYPE : string;

  component BUFG
    port (
      O : out std_ulogic;
      I : in std_ulogic
      );
  end component;
  attribute BOX_TYPE of
    BUFG : component is "PRIMITIVE";

  component BUFR
    generic (
      BUFR_DIVIDE : string := "BYPASS";
      SIM_DEVICE : string := "VIRTEX4"
      );
    port (
      O : out std_ulogic;
      CE : in std_ulogic;
      CLR : in std_ulogic;
      I : in std_ulogic
      );
  end component;
  attribute BOX_TYPE of
    BUFR : component is "PRIMITIVE";

  component BUFH
    port (
      O : out std_ulogic;
      I : in std_ulogic
      );
  end component;
  attribute BOX_TYPE of
    BUFH : component is "PRIMITIVE";

begin

  is_none: if mode_c = "none"
  generate
    clock_o <= clock_i;
  end generate;

  is_region: if mode_c = "region"
  generate
    buf: bufr
      generic map(
        bufr_divide => "BYPASS"
        )
      port map(
        clr => '0',
        ce => '1',
        i => clock_i,
        o => clock_o
        );
  end generate;

  is_row: if mode_c = "row"
  generate
    buf: bufh
      port map(
        i => clock_i,
        o => clock_o
        );
  end generate;

  is_global_or_other: if mode_c /= "none" and mode_c /= "region" and mode_c /= "row"
  generate
    buf: bufg
      port map(
        i => clock_i,
        o => clock_o
        );
  end generate;

end architecture;
