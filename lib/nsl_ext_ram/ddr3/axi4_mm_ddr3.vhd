library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_io, nsl_amba, nsl_ext_ram;
use nsl_ext_ram.timing.all;
use nsl_ext_ram.burst.all;
use nsl_ext_ram.dram.all;
use nsl_ext_ram.ddr3.all;

entity axi4_mm_ddr3 is
  generic(
    part_c: dram_part_t;
    tck_ps_c: natural;
    axi_config_c: nsl_amba.axi4_mm.config_t;
    device_count_c: positive := 1;
    keep_row_open_c: boolean := true
    );
  port(
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic;

    axi_i: in nsl_amba.axi4_mm.master_t;
    axi_o: out nsl_amba.axi4_mm.slave_t;

    ready_o: out std_ulogic;

    ram_ck_o: out nsl_io.diff.diff_pair;
    ram_cke_o: out std_ulogic;
    ram_cs_n_o: out std_ulogic;
    ram_ras_n_o: out std_ulogic;
    ram_cas_n_o: out std_ulogic;
    ram_we_n_o: out std_ulogic;
    ram_ba_o: out unsigned;
    ram_a_o: out unsigned;
    ram_odt_o: out std_ulogic;
    ram_reset_n_o: out std_ulogic;
    ram_dm_o: out std_ulogic_vector;
    ram_dqs_o: out nsl_io.io.tristated_vector;
    ram_dqs_i: in std_ulogic_vector;
    ram_dq_o: out nsl_io.io.tristated_vector;
    ram_dq_i: in std_ulogic_vector
    );
end entity;

architecture beh of axi4_mm_ddr3 is

  signal cmd_s: cmd_t;
  signal cmd_ack_s: cmd_ack_t;
  signal wdata_s: wdata_t;
  signal wdata_ack_s: wdata_ack_t;
  signal rdata_s: rdata_t;
  signal rdata_ack_s: rdata_ack_t;
  signal ready_s: std_ulogic;

begin

  ready_o <= ready_s;

  adapter: nsl_ext_ram.frontend.axi4_mm_burst_adapter
    generic map(
      axi_config_c => axi_config_c,
      cycle_byte_count_c => cycle_byte_count(part_c, device_count_c),
      burst_cycle_count_c => 1
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      axi_i => axi_i,
      axi_o => axi_o,

      cmd_o => cmd_s,
      cmd_i => cmd_ack_s,
      wdata_o => wdata_s,
      wdata_i => wdata_ack_s,
      rdata_i => rdata_s,
      rdata_o => rdata_ack_s,

      ready_i => ready_s
      );

  controller: nsl_ext_ram.ddr3.ddr3_controller
    generic map(
      part_c => part_c,
      tck_ps_c => tck_ps_c,
      device_count_c => device_count_c,
      keep_row_open_c => keep_row_open_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      cmd_i => cmd_s,
      cmd_o => cmd_ack_s,
      wdata_i => wdata_s,
      wdata_o => wdata_ack_s,
      rdata_o => rdata_s,
      rdata_i => rdata_ack_s,

      ready_o => ready_s,

      ram_ck_o => ram_ck_o,
      ram_cke_o => ram_cke_o,
      ram_cs_n_o => ram_cs_n_o,
      ram_ras_n_o => ram_ras_n_o,
      ram_cas_n_o => ram_cas_n_o,
      ram_we_n_o => ram_we_n_o,
      ram_ba_o => ram_ba_o,
      ram_a_o => ram_a_o,
      ram_odt_o => ram_odt_o,
      ram_reset_n_o => ram_reset_n_o,
      ram_dm_o => ram_dm_o,
      ram_dqs_o => ram_dqs_o,
      ram_dqs_i => ram_dqs_i,
      ram_dq_o => ram_dq_o,
      ram_dq_i => ram_dq_i
      );

end architecture;
