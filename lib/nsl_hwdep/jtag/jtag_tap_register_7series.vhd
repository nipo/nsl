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
    reset_n_o : out std_ulogic;
    selected_o: out std_ulogic;
    capture_o : out std_ulogic;
    shift_o   : out std_ulogic;
    update_o  : out std_ulogic;
    tdi_o     : out std_ulogic;
    tdo_i     : in  std_ulogic
    );
end entity;

architecture seven_series of jtag_tap_register is

  signal tck, tdo, reset, capture, selected, update, shift : std_ulogic;
  
begin

  capture_o <= capture and selected;
  update_o <= update and selected;
  shift_o <= shift and selected;
  selected_o <= selected;
  reset_n_o <= not reset;

  inst: bscane2
    generic map(
      jtag_chain => id_c
      )
    port map(
      capture => capture,
      reset   => reset,
      tck     => tck,
      sel     => selected,
      shift   => shift,
      tdi     => tdi_o,
      update  => update,
      tdo     => tdo
      );

  tck_buf: bufg
    port map(
      i => tck,
      o => tck_o
      );
  tdo <= tdo_i;

end architecture;
