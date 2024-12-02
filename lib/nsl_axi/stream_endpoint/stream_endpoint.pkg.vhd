library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_axi;

package stream_endpoint is

  constant AXI4_STREAM_ENDPOINT_LITE_IN_DATA    : integer := 0;
  constant AXI4_STREAM_ENDPOINT_LITE_OUT_DATA   : integer := 1;
  constant AXI4_STREAM_ENDPOINT_LITE_IN_STATUS  : integer := 2;
  constant AXI4_STREAM_ENDPOINT_LITE_OUT_STATUS : integer := 3;
  constant AXI4_STREAM_ENDPOINT_LITE_IRQ_STATE  : integer := 4;
  constant AXI4_STREAM_ENDPOINT_LITE_IRQ_MASK   : integer := 5;
  
  component axi4_stream_endpoint_lite is
    generic (
      mm_config_c : nsl_axi.axi4_mm.config_t;
      stream_config_c : nsl_axi.axi4_stream.config_t;
      out_buffer_depth_c: natural range 4 to 4096;
      in_buffer_depth_c: natural range 4 to 4096
      );
    port (
      clock_i: in std_ulogic;
      reset_n_i: in std_ulogic;

      irq_n_o : out std_ulogic;

      mm_i : in nsl_axi.axi4_mm.master_t;
      mm_o : out nsl_axi.axi4_mm.slave_t;
      
      rx_i : in nsl_axi.axi4_stream.master_t;
      rx_o : out nsl_axi.axi4_stream.slave_t;
      
      tx_o : out nsl_axi.axi4_stream.master_t;
      tx_i : in nsl_axi.axi4_stream.slave_t
      );
  end component;

end package;
