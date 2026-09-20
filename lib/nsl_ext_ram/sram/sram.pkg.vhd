library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_io, nsl_ext_ram;
use nsl_ext_ram.timing.all;
use nsl_ext_ram.burst.all;

-- Controller for a synchronous SRAM, and its AXI4-MM port.
package sram is

  -- Bytes one controller cycle carries.
  function cycle_byte_count(part_c: sram_part_t) return natural;

  -- Byte address space of the part, parity aside.
  function byte_address_width(part_c: sram_part_t) return natural;

  function axi_config(part_c: sram_part_t;
                      id_width: natural := 4)
    return nsl_amba.axi4_mm.config_t;

  component sram_core is
    generic(
      part_c: sram_part_t;
      timing_c: sram_timing_t;
      burst_cycle_count_c: natural
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

      io_o: out nsl_ext_ram.sram_io.master_t;
      io_i: in nsl_ext_ram.sram_io.slave_t
      );
  end component;

  component sram_controller is
    generic(
      part_c: sram_part_t;
      tck_ps_c: natural;
      -- Words one access transfers
      burst_cycle_count_c: natural := 4;
      -- Controller cycles a read takes on top of the part's own
      -- latency.  One, for the register that captures the bus: the
      -- output register costs nothing because the forwarded clock is
      -- what moves against it.  Raise it when the round trip no longer
      -- fits inside a cycle.
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
  end component;

  component axi4_mm_sram is
    generic(
      part_c: sram_part_t;
      tck_ps_c: natural;
      axi_config_c: nsl_amba.axi4_mm.config_t;
      burst_cycle_count_c: natural := 4;
      capture_ck_c: natural := 1
      );
    port(
      clock_i: in std_ulogic;
      reset_n_i: in std_ulogic;

      axi_i: in nsl_amba.axi4_mm.master_t;
      axi_o: out nsl_amba.axi4_mm.slave_t;

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
  end component;

end package sram;

package body sram is

  function cycle_byte_count(part_c: sram_part_t) return natural
  is
  begin
    return part_c.dq_byte_count;
  end function;

  function byte_address_width(part_c: sram_part_t) return natural
  is
  begin
    return device_byte_count_l2(part_c);
  end function;

  function axi_config(part_c: sram_part_t;
                      id_width: natural := 4)
    return nsl_amba.axi4_mm.config_t
  is
  begin
    return nsl_ext_ram.frontend.axi_config(
      cycle_byte_count => cycle_byte_count(part_c),
      byte_address_width => byte_address_width(part_c),
      id_width => id_width);
  end function;

end package body sram;
