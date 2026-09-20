library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_io, nsl_math, nsl_amba, nsl_ext_ram;
use nsl_ext_ram.timing.all;
use nsl_ext_ram.dfi.all;
use nsl_ext_ram.burst.all;
use nsl_ext_ram.dram.all;

-- Controller for a single data rate SDRAM: the generation-independent
-- core, the power-up sequence the part expects, and the PHY, wired
-- together and parameterised from the part and the clock period.
package sdram is

  -- Address bus a part needs: enough for a row, and always enough to
  -- reach A10, which carries the precharge-all and auto precharge
  -- flags.
  function address_width(part_c: dram_part_t) return natural;

  -- DFI configuration a single data rate part runs with.
  function dfi_config(part_c: dram_part_t) return config_t;

  -- Bytes one controller cycle, and so one bus beat, carries.
  function cycle_byte_count(part_c: dram_part_t) return natural;

  -- Byte address space of the part, given how long a burst is.
  function byte_address_width(part_c: dram_part_t;
                              burst_length_l2: natural) return natural;

  -- AXI configuration the controller's port runs with.
  function axi_config(part_c: dram_part_t;
                      burst_length_l2: natural := 3;
                      id_width: natural := 4) return nsl_amba.axi4_mm.config_t;

  component sdram_controller is
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
  end component;

  -- Controller with an AXI4-MM port.  Bus width follows what one
  -- controller cycle carries; put a width converter in front for
  -- anything else.
  component axi4_mm_sdram is
    generic(
      part_c: dram_part_t;
      tck_ps_c: natural;
      axi_config_c: nsl_amba.axi4_mm.config_t;
      burst_length_l2_c: natural := 3;
      keep_row_open_c: boolean := true;
      capture_ck_c: natural := 2;
      capture_on_fall_c: boolean := true
      );
    port(
      clock_i: in std_ulogic;
      reset_n_i: in std_ulogic;

      axi_i: in nsl_amba.axi4_mm.master_t;
      axi_o: out nsl_amba.axi4_mm.slave_t;

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
  end component;

end package sdram;

package body sdram is

  function address_width(part_c: dram_part_t) return natural
  is
  begin
    return nsl_math.arith.max(part_c.row_count_l2, 11);
  end function;

  function dfi_config(part_c: dram_part_t) return config_t
  is
  begin
    return config(phase_count => 1,
                  edge_count => 1,
                  dq_width => part_c.dq_width,
                  bank_width => part_c.bank_count_l2,
                  address_width => address_width(part_c));
  end function;

  function cycle_byte_count(part_c: dram_part_t) return natural
  is
  begin
    return part_c.dq_width / 8;
  end function;

  function byte_address_width(part_c: dram_part_t;
                              burst_length_l2: natural) return natural
  is
  begin
    return layout(part_c, dfi_config(part_c),
                  burst_length_l2).byte_address_width;
  end function;

  function axi_config(part_c: dram_part_t;
                      burst_length_l2: natural := 3;
                      id_width: natural := 4) return nsl_amba.axi4_mm.config_t
  is
  begin
    return nsl_ext_ram.frontend.axi_config(
      cycle_byte_count => cycle_byte_count(part_c),
      byte_address_width => byte_address_width(part_c, burst_length_l2),
      id_width => id_width);
  end function;

end package body sdram;
