library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library unisim;
use unisim.vcomponents.all;

entity jtag_tap_register is
  generic(
    id_c    : natural range 1 to 4
    );
  port(
    tck_o     : out std_ulogic;
    reset_o   : out std_ulogic;
    selected_o: out std_ulogic;
    capture_o : out std_ulogic;
    shift_o   : out std_ulogic;
    update_o  : out std_ulogic;
    tdi_o     : out std_ulogic;
    tdo_i     : in  std_ulogic
    );
end entity;

architecture seven_series of jtag_tap_register is
begin

  inst: bscane2
    generic map(
      jtag_chain => id_c
      )
    port map(
      capture => capture_o,
      reset   => reset_o,
      tck     => tck_o,
      sel     => selected_o,
      shift   => shift_o,
      tdi     => tdi_o,
      update  => update_o,
      tdo     => tdo_i
      );

end architecture;
