library ieee;
use ieee.std_logic_1164.all;

library unisim;
use unisim.vcomponents.all;

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
begin

  is_none: if mode_c = "none"
  generate
    clock_o <= clock_i;
  end generate;

  is_region: if mode_c = "region"
  generate
    buf: unisim.vcomponents.bufr
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
    buf: unisim.vcomponents.bufh
      port map(
        i => clock_i,
        o => clock_o
        );
  end generate;

  is_global_or_other: if mode_c /= "none" and mode_c /= "region" and mode_c /= "row"
  generate
    buf: unisim.vcomponents.bufg
      port map(
        i => clock_i,
        o => clock_o
        );
  end generate;

end architecture;
