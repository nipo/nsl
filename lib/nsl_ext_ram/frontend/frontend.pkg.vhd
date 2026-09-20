library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_ext_ram;
use nsl_amba.axi4_mm.all;

-- AXI4-MM face of an external memory controller.
package frontend is

  -- Configuration a controller's port runs with.  Data width follows
  -- what one controller cycle carries, which is the only width where
  -- the memory bus is neither starved nor idle; anything else belongs
  -- behind a width converter.
  function axi_config(cycle_byte_count: natural;
                      byte_address_width: natural;
                      id_width: natural := 4;
                      max_length: natural := 256) return config_t;

  component axi4_mm_burst_adapter is
    generic(
      axi_config_c: config_t;
      cycle_byte_count_c: natural;
      burst_cycle_count_c: natural
      );
    port(
      clock_i: in std_ulogic;
      reset_n_i: in std_ulogic;

      axi_i: in master_t;
      axi_o: out slave_t;

      cmd_o: out nsl_ext_ram.burst.cmd_t;
      cmd_i: in nsl_ext_ram.burst.cmd_ack_t;
      wdata_o: out nsl_ext_ram.burst.wdata_t;
      wdata_i: in nsl_ext_ram.burst.wdata_ack_t;
      rdata_i: in nsl_ext_ram.burst.rdata_t;
      rdata_o: out nsl_ext_ram.burst.rdata_ack_t;

      ready_i: in std_ulogic
      );
  end component;

end package frontend;

package body frontend is

  function axi_config(cycle_byte_count: natural;
                      byte_address_width: natural;
                      id_width: natural := 4;
                      max_length: natural := 256) return config_t
  is
  begin
    return config(address_width => byte_address_width,
                  data_bus_width => cycle_byte_count * 8,
                  id_width => id_width,
                  max_length => max_length,
                  size => true,
                  burst => true);
  end function;

end package body frontend;
