library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_io, nsl_ext_ram;
use nsl_ext_ram.timing.all;
use nsl_ext_ram.dfi.all;
use nsl_ext_ram.burst.all;
use nsl_ext_ram.dram.all;
use nsl_ext_ram.sdram.all;

entity sdram_controller is
  generic(
    part_c: dram_part_t;
    tck_ps_c: natural;
    burst_length_l2_c: natural := 3;
    keep_row_open_c: boolean := true;
    capture_ck_c: natural := 2;
    capture_on_fall_c: boolean := true
    );
  port(
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic;

    cmd_i: in cmd_t;
    cmd_o: out cmd_ack_t;
    wdata_i: in wdata_t;
    wdata_o: out wdata_ack_t;
    rdata_o: out rdata_t;
    rdata_i: in rdata_ack_t;

    ready_o: out std_ulogic;

    ram_clock_o: out std_ulogic;
    ram_cke_o: out std_ulogic;
    ram_cs_n_o: out std_ulogic;
    ram_ras_n_o: out std_ulogic;
    ram_cas_n_o: out std_ulogic;
    ram_we_n_o: out std_ulogic;
    ram_ba_o: out unsigned;
    ram_a_o: out unsigned;
    ram_dqm_o: out std_ulogic_vector;
    ram_dq_o: out nsl_io.io.tristated_vector;
    ram_dq_i: in std_ulogic_vector
    );
end entity;

architecture beh of sdram_controller is

  constant timing_c: dram_timing_t := timings(part_c, tck_ps_c);
  constant dfi_config_c: config_t := dfi_config(part_c);
  constant script_c: init_script_t
    := sdram_init_script(part_c, timing_c, burst_length_l2_c,
                         dfi_config_c.phase_count);

  signal dfi_master_s: master_t;
  signal dfi_slave_s: slave_t;

begin

  core: nsl_ext_ram.dram.dram_core
    generic map(
      part_c => part_c,
      timing_c => timing_c,
      dfi_config_c => dfi_config_c,
      script_c => script_c,
      burst_length_l2_c => burst_length_l2_c,
      keep_row_open_c => keep_row_open_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      cmd_i => cmd_i,
      cmd_o => cmd_o,
      wdata_i => wdata_i,
      wdata_o => wdata_o,
      rdata_o => rdata_o,
      rdata_i => rdata_i,

      ready_o => ready_o,

      dfi_o => dfi_master_s,
      dfi_i => dfi_slave_s
      );

  phy: nsl_ext_ram.sdram_io.sdram_phy
    generic map(
      part_c => part_c,
      timing_c => timing_c,
      dfi_config_c => dfi_config_c,
      capture_ck_c => capture_ck_c,
      capture_on_fall_c => capture_on_fall_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      dfi_i => dfi_master_s,
      dfi_o => dfi_slave_s,

      clock_o => ram_clock_o,
      cke_o => ram_cke_o,
      cs_n_o => ram_cs_n_o,
      ras_n_o => ram_ras_n_o,
      cas_n_o => ram_cas_n_o,
      we_n_o => ram_we_n_o,
      ba_o => ram_ba_o,
      a_o => ram_a_o,
      dqm_o => ram_dqm_o,
      dq_o => ram_dq_o,
      dq_i => ram_dq_i
      );

end architecture;
