library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;

-- AXI4-MM routing components for building interconnect fabrics.
package mm_routing is

  -- Error slave that responds with DECERR to all transactions.
  -- Useful for handling unmapped address ranges.
  component axi4_mm_error_slave is
    generic(
      config_c : work.axi4_mm.config_t
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      axi_i : in work.axi4_mm.master_t;
      axi_o : out work.axi4_mm.slave_t
      );
  end component;

  -- Full N-to-M AXI4-MM crossbar interconnect.
  -- Connects N masters to M slaves with address-based routing.
  -- ID field is widened to encode master index for response routing.
  --
  -- slave_config_c.id_width must be >= master_config_c.id_width +
  -- ceil_log2(master_count_c) to accommodate master index in ID field.
  -- Other config fields (address_width, data_bus_width_l2, len_width)
  -- must match between master and slave configs.
  --
  -- default_slave_c controls handling of unmapped addresses:
  -- - If < 0: an internal error slave is instantiated, unmapped accesses return DECERR
  -- - If >= 0: unmapped addresses route to the external slave at that index
  --
  -- Write data reaches each slave in the order its write addresses
  -- were accepted.
  --
  -- aw_tracking_depth_c sets the depth of the per-master and per-slave
  -- FIFOs that correlate AW and W channels. This limits how many
  -- write transactions each master can have, and each slave can
  -- receive, with address accepted but data not forwarded yet, before
  -- AW blocks.  Increase if masters issue many back-to-back write
  -- addresses before sending data.
  --
  -- Each master may only have reads outstanding to one slave at a
  -- time, and writes outstanding to one slave at a time.  A read
  -- (resp. write) to another slave waits until all previous ones got
  -- their response.  This keeps responses in order whatever the IDs,
  -- and avoids write data deadlocks between masters.  Write data may
  -- reach a slave before its address.
  --
  -- max_outstanding_c limits how many reads, and how many writes,
  -- each master can have waiting for a response.
  --
  -- master_slice_c (resp. slave_slice_c) inserts a register slice on
  -- all channels of each master (resp. slave) side port.  Paths
  -- through the crossbar are combinational, slices on both sides
  -- isolate them from the outside.
  component axi4_mm_crossbar is
    generic(
      master_config_c : work.axi4_mm.config_t;
      slave_config_c : work.axi4_mm.config_t;
      master_count_c : positive;
      routing_table_c : work.address.address_vector;
      default_slave_c : integer := -1;
      aw_tracking_depth_c : positive := 4;
      max_outstanding_c : positive := 16;
      master_slice_c : boolean := false;
      slave_slice_c : boolean := false
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      -- From masters, use master_config_c
      slave_i : in work.axi4_mm.master_vector(0 to master_count_c-1);
      slave_o : out work.axi4_mm.slave_vector(0 to master_count_c-1);

      -- To slaves, use slave_config_c
      master_o : out work.axi4_mm.master_vector(0 to routing_table_c'length-1);
      master_i : in work.axi4_mm.slave_vector(0 to routing_table_c'length-1)
      );
  end component;

  -- Shared bus N-to-M AXI4-MM interconnect.
  -- Low-cost alternative to crossbar: only one transaction at a time globally.
  -- Trades throughput for minimal logic and wire count.
  --
  -- Features:
  -- - Single outstanding transaction globally
  -- - No pipelining
  -- - Fixed priority arbitration: lower master index first
  -- - IDs pass through
  -- - Writes take priority over reads from same master
  --
  -- default_slave_c controls handling of unmapped addresses:
  -- - If < 0: an internal error slave is instantiated, unmapped accesses return DECERR
  -- - If >= 0: unmapped addresses route to the external slave at that index
  component axi4_mm_shared_bus is
    generic(
      config_c : work.axi4_mm.config_t;
      master_count_c : positive;
      routing_table_c : work.address.address_vector;
      default_slave_c : integer := -1
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      -- From masters
      slave_i : in work.axi4_mm.master_vector(0 to master_count_c-1);
      slave_o : out work.axi4_mm.slave_vector(0 to master_count_c-1);

      -- To slaves
      master_o : out work.axi4_mm.master_vector(0 to routing_table_c'length-1);
      master_i : in work.axi4_mm.slave_vector(0 to routing_table_c'length-1)
      );
  end component;

end package mm_routing;
