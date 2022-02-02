library ieee;
use ieee.std_logic_1164.all;

library unisim;

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

  assert user_port_count_c <= 4 and user_port_count_c >= 1
    report "Bad user port count, supports 1 to 4"
    severity failure;

end entity;

architecture s6 of jtag_user_tap is

  signal run_s, tck_unb_s, reset_s, selected_s, capture_s, shift_s, update_s, tdi_s, tdo_s: std_ulogic_vector(0 to user_port_count_c-1);
  signal tck_s : std_ulogic;
  
begin

  insts: for i in 0 to user_port_count_c-1
  generate
    inst: unisim.vcomponents.bscan_spartan6
    generic map(
      jtag_chain => i+1
      )
    port map(
      capture => capture_s(i),
      reset   => reset_s(i),
      tck     => tck_unb_s(i),
      sel     => selected_s(i),
      shift   => shift_s(i),
      tdi     => tdi_s(i),
      runtest => run_s(i),
      update  => update_s(i),
      tdo     => tdo_s(i)
      );
  end generate;

  tck_buf: unisim.vcomponents.bufg
    port map(
      i => tck_unb_s(0),
      o => tck_s
      );

  tck_o <= tck_s;
  tdo_s <= tdo_i;
  tdi_o <= tdi_s(0);
  run_o <= run_s(0);
  shift_o <= shift_s(0);
  capture_o <= capture_s(0);
  update_o <= update_s(0);
  selected_o <= selected_s;
  tlr_o <= reset_s(0);
  
end architecture;
