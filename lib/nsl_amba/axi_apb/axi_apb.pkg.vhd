library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba;

package axi_apb is
  
  component axi4_apb_bridge is
    generic (
      axi_config_c : nsl_amba.axi4_mm.config_t;
      apb_config_c : nsl_amba.apb.config_t
      );
    port (
      clock_i: in std_ulogic;
      reset_n_i: in std_ulogic;

      irq_n_o : out std_ulogic;

      axi_i : in nsl_amba.axi4_mm.master_t;
      axi_o : out nsl_amba.axi4_mm.slave_t;
      
      apb_o : out nsl_amba.apb.master_t;
      apb_i : in nsl_amba.apb.slave_t
      );
  end component;
  
  component axi4_apb_bridge_dispatch is
    generic (
      axi_config_c : nsl_amba.axi4_mm.config_t;
      apb_config_c : nsl_amba.apb.config_t;
      routing_table_c : nsl_amba.address.address_vector
      );
    port (
      clock_i: in std_ulogic;
      reset_n_i: in std_ulogic;

      irq_n_o : out std_ulogic;

      axi_i : in nsl_amba.axi4_mm.master_t;
      axi_o : out nsl_amba.axi4_mm.slave_t;
      
      apb_o : out nsl_amba.apb.master_vector(0 to routing_table_c'length-1);
      apb_i : in nsl_amba.apb.slave_vector(0 to routing_table_c'length-1)
      );
  end component;

end package;
