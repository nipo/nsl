library ieee;
use ieee.std_logic_1164.all;

library nsl_amba, nsl_jtag;

entity jtag_apb_master_tap is
  generic(
    config_c : nsl_amba.apb.config_t;
    node_vendor_c : natural range 0 to 2047 := 16#5ff#;
    node_type_c : natural range 0 to 255 := 16#02#;
    node_version_c : natural range 0 to 15 := 0
    );
  port(
    chip_tck_i : in std_ulogic := '0';
    chip_tms_i : in std_ulogic := '0';
    chip_tdi_i : in std_ulogic := '0';
    chip_tdo_o : out std_ulogic;

    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    apb_o : out nsl_amba.apb.master_t;
    apb_i : in nsl_amba.apb.slave_t
    );
end entity;

architecture beh of jtag_apb_master_tap is

  signal tck_s, tdi_s, tdo_s, selected_s, capture_s, shift_s, update_s : std_ulogic;

begin

  tap: nsl_jtag.user_tap.jtag_user_tap
    generic map(
      user_port_count_c => 1,
      node_vendor_c => node_vendor_c,
      node_type_c => node_type_c,
      node_version_c => node_version_c
      )
    port map(
      chip_tck_i => chip_tck_i,
      chip_tms_i => chip_tms_i,
      chip_tdi_i => chip_tdi_i,
      chip_tdo_o => chip_tdo_o,

      tdo_i(0) => tdo_s,
      selected_o(0) => selected_s,
      tck_o => tck_s,
      tdi_o => tdi_s,
      shift_o => shift_s,
      capture_o => capture_s,
      update_o => update_s
      );

  master: nsl_jtag.apb_master.jtag_apb_master
    generic map(
      config_c => config_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      tck_i => tck_s,
      tdi_i => tdi_s,
      tdo_o => tdo_s,
      selected_i => selected_s,
      capture_i => capture_s,
      shift_i => shift_s,
      update_i => update_s,

      apb_o => apb_o,
      apb_i => apb_i
      );

end architecture;
