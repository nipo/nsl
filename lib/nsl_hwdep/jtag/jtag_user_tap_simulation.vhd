library ieee;
use ieee.std_logic_1164.all;

library nsl_simulation;

entity jtag_user_tap is
  generic(
    user_port_count_c : integer := 1
    );
  port(
    chip_tck_i : in std_ulogic := '0';
    chip_tms_i : in std_ulogic := '0';
    chip_tdi_i : in std_ulogic := '0';
    chip_tdo_o : out std_ulogic;

    tdo_i : in std_ulogic_vector(0 to user_port_count_c-1);
    selected_o : out std_ulogic_vector(0 to user_port_count_c-1);
    run_o : out std_ulogic;
    tck_o : out std_ulogic;
    tdi_o : out std_ulogic;
    tlr_o : out std_ulogic;
    shift_o : out std_ulogic;
    capture_o : out std_ulogic;
    update_o : out std_ulogic
    );
begin

  assert user_port_count_c <= nsl_simulation.jtag.max_reg_count_c and user_port_count_c >= 1
    report "Bad user port count, supports 1 to " & integer'image(nsl_simulation.jtag.max_reg_count_c)
    severity failure;

end entity;

architecture sim of jtag_user_tap is
  
begin

  insts: for i in 0 to user_port_count_c
  generate
  begin
    inst: nsl_simulation.jtag.jtag_sim_reg
      generic map(
        index_c => i - 1
        )
      port map(
        selected_o => selected_o(i),
        tdo_i => tdo_i(i)
        );
  end generate;

  run_o <= nsl_simulation.jtag.rti_g;
  tck_o <= nsl_simulation.jtag.tck_g;
  tdi_o <= nsl_simulation.jtag.tdi_g;
  tlr_o <= nsl_simulation.jtag.tlr_g;
  shift_o <= nsl_simulation.jtag.dr_shift_g;
  capture_o <= nsl_simulation.jtag.dr_capture_g;
  update_o <= nsl_simulation.jtag.dr_update_g;
  
end architecture;
