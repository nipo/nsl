library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.jtag.all;

entity jtag_sim_reg is
  generic(
    index_c : natural
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

architecture beh of jtag_sim_reg is

begin

  tck_o <= tck_g;
  tlr_o <= tlr_g;
  selected_o <= '1' when reg_sel_g = index_c else '0';
  capture_o <= dr_capture_g when reg_sel_g = index_c else '0';
  shift_o <= dr_shift_g when reg_sel_g = index_c else '0';
  update_o <= dr_update_g when reg_sel_g = index_c else '0';
  run_o <= rti_g when reg_sel_g = index_c else '0';
  tdi_o <= tdi_g;
  reg_tdo_g(index_c) <= tdo_i;

end architecture;
