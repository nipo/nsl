library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_io, nsl_math, nsl_amba, nsl_ext_ram;
use nsl_ext_ram.timing.all;
use nsl_ext_ram.dfi.all;
use nsl_ext_ram.burst.all;
use nsl_ext_ram.dram.all;

-- Controller for a DDR3 part: the generation-independent core, the
-- power-up sequence DDR3 asks for, and the PHY.
--
-- A burst of eight lands in one controller cycle when the PHY runs
-- four phases, so the bus carries a whole memory access per beat and
-- the controller clock is a quarter of the memory clock.
package ddr3 is

  function address_width(part_c: dram_part_t) return natural;

  -- Phases a controller cycle is cut into so that a burst of eight
  -- fills exactly one cycle.
  function phase_count(part_c: dram_part_t) return natural;

  function dfi_config(part_c: dram_part_t;
                      device_count: positive := 1) return config_t;

  -- Bytes one controller cycle, and so one bus beat, carries.
  function cycle_byte_count(part_c: dram_part_t;
                            device_count: positive := 1) return natural;

  function byte_address_width(part_c: dram_part_t;
                              device_count: positive := 1) return natural;

  function axi_config(part_c: dram_part_t;
                      device_count: positive := 1;
                      id_width: natural := 4)
    return nsl_amba.axi4_mm.config_t;

  component ddr3_controller is
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
  end component;

  component axi4_mm_ddr3 is
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
  end component;

end package ddr3;

package body ddr3 is

  function address_width(part_c: dram_part_t) return natural
  is
  begin
    return nsl_math.arith.max(part_c.row_count_l2, 11);
  end function;

  function phase_count(part_c: dram_part_t) return natural
  is
  begin
    return 2 ** part_c.prefetch_l2 / 2;
  end function;

  function dfi_config(part_c: dram_part_t;
                      device_count: positive := 1) return config_t
  is
  begin
    return config(phase_count => phase_count(part_c),
                  edge_count => 2,
                  dq_width => part_c.dq_width * device_count,
                  bank_width => part_c.bank_count_l2,
                  address_width => address_width(part_c),
                  odt => true,
                  reset => true);
  end function;

  function cycle_byte_count(part_c: dram_part_t;
                            device_count: positive := 1) return natural
  is
  begin
    return nsl_ext_ram.dfi.cycle_byte_count(dfi_config(part_c, device_count));
  end function;

  function byte_address_width(part_c: dram_part_t;
                              device_count: positive := 1) return natural
  is
  begin
    return layout(part_c, dfi_config(part_c, device_count),
                  part_c.prefetch_l2).byte_address_width;
  end function;

  function axi_config(part_c: dram_part_t;
                      device_count: positive := 1;
                      id_width: natural := 4)
    return nsl_amba.axi4_mm.config_t
  is
  begin
    return nsl_ext_ram.frontend.axi_config(
      cycle_byte_count => cycle_byte_count(part_c, device_count),
      byte_address_width => byte_address_width(part_c, device_count),
      id_width => id_width);
  end function;

end package body ddr3;
