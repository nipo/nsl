library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library unisim;
use unisim.vcomponents.all;

entity jtag_tap_register is
  generic(
    id    : natural range 1 to 4
    );
  port(
    p_tck     : out std_ulogic;
    p_reset   : out std_ulogic;
    p_selected: out std_ulogic;
    p_capture : out std_ulogic;
    p_shift   : out std_ulogic;
    p_update  : out std_ulogic;
    p_tdi     : out std_ulogic;
    p_tdo     : in  std_ulogic
    );
end entity;

architecture spartan6 of jtag_tap_register is
begin

  inst: bscan_spartan6
    generic map(
      jtag_chain => id
      )
    port map(
      capture => p_capture,
      reset   => p_reset,
      tck     => p_tck,
      sel     => p_selected,
      shift   => p_shift,
      tdi     => p_tdi,
      update  => p_update,
      tdo     => p_tdo
      );

end architecture;
