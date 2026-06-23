library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_simulation;

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

architecture sim of jtag_tap_register is
  
begin

  inst: nsl_simulation.jtag.jtag_sim_reg
    generic map(
      index_c => id_c - 1
      )
    port map(
      tck_o => tck_o,
      tlr_o => tlr_o,
      selected_o => selected_o,
      capture_o => capture_o,
      shift_o => shift_o,
      update_o => update_o,
      run_o => run_o,
      tdi_o => tdi_o,
      tdo_i => tdo_i
      );
  
end architecture;
