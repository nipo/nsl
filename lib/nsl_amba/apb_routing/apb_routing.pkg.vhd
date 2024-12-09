library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba;
use nsl_amba.apb.all;

package apb_routing is

  component apb_dispatch is
    generic(
      config_c : config_t;
      routing_table_c : nsl_amba.address.address_vector
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      in_i : in master_t;
      in_o : out slave_t;

      out_o : out master_vector(0 to routing_table_c'length-1);
      out_i : in slave_vector(0 to routing_table_c'length-1)
      );
  end component;

end package apb_routing;
