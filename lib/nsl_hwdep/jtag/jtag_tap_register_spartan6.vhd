library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity jtag_tap_register is
  generic(
    id_c    : natural range 1 to 4
    );
  port(
    tck_o     : out std_ulogic;
    tlr_o : out std_ulogic;
    selected_o: out std_ulogic;
    capture_o : out std_ulogic;
    shift_o   : out std_ulogic;
    update_o  : out std_ulogic;
    run_o  : out std_ulogic;
    tdi_o     : out std_ulogic;
    tdo_i     : in  std_ulogic
    );
end entity;

architecture spartan6 of jtag_tap_register is

  attribute BOX_TYPE : string;
  component BSCAN_SPARTAN6
    generic (
      JTAG_CHAIN : integer := 1
      );
    port (
      CAPTURE : out std_ulogic := 'H';
      DRCK : out std_ulogic := 'H';
      RESET : out std_ulogic := 'H';
      RUNTEST : out std_ulogic := 'L';
      SEL : out std_ulogic := 'L';
      SHIFT : out std_ulogic := 'L';
      TCK : out std_ulogic := 'L';
      TDI : out std_ulogic := 'L';
      TMS : out std_ulogic := 'L';
      UPDATE : out std_ulogic := 'L';
      TDO : in std_ulogic := 'X'
      );
  end component;
  attribute BOX_TYPE of
    BSCAN_SPARTAN6 : component is "PRIMITIVE";
  component BUFG
    port (
      O : out std_ulogic;
      I : in std_ulogic
      );
  end component;
  attribute BOX_TYPE of
    BUFG : component is "PRIMITIVE";

  signal run, tck, tdo, reset, capture, selected, update, shift : std_ulogic;

  attribute period: string;
  attribute period of tck : signal is "20 ns";
  
begin

  capture_o <= capture;
  update_o <= update;
  shift_o <= shift;
  selected_o <= selected;
  tlr_o <= reset;
  run_o <= run;
  
  inst: bscan_spartan6
    generic map(
      jtag_chain => id_c
      )
    port map(
      capture => capture,
      reset   => reset,
      tck     => tck,
      sel     => selected,
      shift   => shift,
      runtest => run,
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
