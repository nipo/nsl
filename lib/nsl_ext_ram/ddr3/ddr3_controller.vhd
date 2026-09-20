library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_io, nsl_ext_ram;
use nsl_ext_ram.timing.all;
use nsl_ext_ram.dfi.all;
use nsl_ext_ram.burst.all;
use nsl_ext_ram.dram.all;
use nsl_ext_ram.ddr3.all;

entity ddr3_controller is
  generic(
    part_c: dram_part_t;
    tck_ps_c: natural;
    device_count_c: positive := 1;
    keep_row_open_c: boolean := true
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

architecture beh of ddr3_controller is

  constant timing_c: dram_timing_t := timings(part_c, tck_ps_c);
  constant dfi_config_c: config_t := dfi_config(part_c, device_count_c);
  constant script_c: init_script_t
    := ddr3_init_script(part_c, timing_c, dfi_config_c.phase_count);

  signal dfi_master_s: master_t;
  signal dfi_slave_s: slave_t;

begin

  core: nsl_ext_ram.dram.dram_core
    generic map(
      part_c => part_c,
      timing_c => timing_c,
      dfi_config_c => dfi_config_c,
      script_c => script_c,
      burst_length_l2_c => part_c.prefetch_l2,
      keep_row_open_c => keep_row_open_c,
      -- Both DDR3 PHYs of this library read rddata_en as DFI states
      -- it, a cycle of level per cycle of answer, and both lay write
      -- bursts back to back with no preamble between them.  So the
      -- column pipeline runs at tCCD in either direction and what is
      -- left to size is how far ahead reads may be announced.
      --
      -- A read is answered read_offset / slot_count + 3 cycles after
      -- its command: the offset is where in the announcement queue the
      -- answer is read out, and the three are the registers the DFI
      -- input, the queue entry and the answer itself sit in.  The
      -- offset port carries six bits, so that round trip never exceeds
      -- eleven cycles, and announcing eleven reads at once is enough
      -- to keep a read command going out every cycle on any board the
      -- PHY can be given.  The simulation PHY's round trip is four.
      read_ahead_c => 11,
      write_overlap_c => true
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

  phy: nsl_ext_ram.ddr3_io.ddr3_phy
    generic map(
      part_c => part_c,
      timing_c => timing_c,
      dfi_config_c => dfi_config_c,
      tck_ps_c => tck_ps_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      dfi_i => dfi_master_s,
      dfi_o => dfi_slave_s,

      ck_o => ram_ck_o,
      cke_o => ram_cke_o,
      cs_n_o => ram_cs_n_o,
      ras_n_o => ram_ras_n_o,
      cas_n_o => ram_cas_n_o,
      we_n_o => ram_we_n_o,
      ba_o => ram_ba_o,
      a_o => ram_a_o,
      odt_o => ram_odt_o,
      ram_reset_n_o => ram_reset_n_o,

      dm_o => ram_dm_o,
      dqs_o => ram_dqs_o,
      dqs_i => ram_dqs_i,
      dq_o => ram_dq_o,
      dq_i => ram_dq_i
      );

end architecture;
