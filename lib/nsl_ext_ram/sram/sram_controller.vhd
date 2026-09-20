library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_io, nsl_ext_ram;
use nsl_ext_ram.timing.all;
use nsl_ext_ram.burst.all;
use nsl_ext_ram.sram.all;

-- Core and pin logic of a synchronous SRAM controller, presenting
-- whole-burst accesses on one side and the part's pins on the other.
entity sram_controller is
  generic(
    part_c: sram_part_t;
    tck_ps_c: natural;
    burst_cycle_count_c: natural := 4;
    capture_ck_c: natural := 1
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
    parity_error_o: out std_ulogic;

    ram_clock_o: out std_ulogic;
    ram_cs_n_o: out std_ulogic;
    ram_cen_n_o: out std_ulogic;
    ram_we_n_o: out std_ulogic;
    ram_bw_n_o: out std_ulogic_vector;
    ram_oe_n_o: out std_ulogic;
    ram_a_o: out unsigned;
    ram_dq_o: out nsl_io.io.tristated_vector;
    ram_dq_i: in std_ulogic_vector;
    ram_dqp_o: out nsl_io.io.tristated_vector;
    ram_dqp_i: in std_ulogic_vector
    );
end entity;

architecture beh of sram_controller is

  constant timing_c: sram_timing_t := timings(part_c, tck_ps_c);

  signal io_master_s: nsl_ext_ram.sram_io.master_t;
  signal io_slave_s: nsl_ext_ram.sram_io.slave_t;

begin

  core: nsl_ext_ram.sram.sram_core
    generic map(
      part_c => part_c,
      timing_c => timing_c,
      burst_cycle_count_c => burst_cycle_count_c
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
      parity_error_o => parity_error_o,

      io_o => io_master_s,
      io_i => io_slave_s
      );

  phy: nsl_ext_ram.sram_io.sram_phy
    generic map(
      part_c => part_c,
      timing_c => timing_c,
      read_delay_ck_c => timing_c.read_latency + capture_ck_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      io_i => io_master_s,
      io_o => io_slave_s,

      clock_o => ram_clock_o,
      cs_n_o => ram_cs_n_o,
      cen_n_o => ram_cen_n_o,
      we_n_o => ram_we_n_o,
      bw_n_o => ram_bw_n_o,
      oe_n_o => ram_oe_n_o,
      a_o => ram_a_o,
      dq_o => ram_dq_o,
      dq_i => ram_dq_i,
      dqp_o => ram_dqp_o,
      dqp_i => ram_dqp_i
      );

end architecture;
