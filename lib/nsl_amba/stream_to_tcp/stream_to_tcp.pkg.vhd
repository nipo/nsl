library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba;

package stream_to_tcp is
  
  component axi4_stream_tcp_gateway is
    generic (
      config_c : nsl_amba.axi4_stream.config_t;
      bind_port_c : natural range 1 to 65535
      );
    port (
      clock_i: in std_ulogic;
      reset_n_i: in std_ulogic;
      
      tx_i : in nsl_amba.axi4_stream.master_t;
      tx_o : out nsl_amba.axi4_stream.slave_t;
      
      rx_o : out nsl_amba.axi4_stream.master_t;
      rx_i : in nsl_amba.axi4_stream.slave_t
      );
  end component;

end package;
