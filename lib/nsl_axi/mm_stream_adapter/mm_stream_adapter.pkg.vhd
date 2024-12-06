library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_axi;
use nsl_axi.axi4_mm.all;
use nsl_axi.axi4_stream.all;

package mm_stream_adapter is

  component axi4_mm_on_stream is
    generic (
      mm_config_c : nsl_axi.axi4_mm.config_t;
      stream_config_c : nsl_axi.axi4_stream.config_t
      );
    port (
      clock_i: in std_ulogic;
      reset_n_i: in std_ulogic;

      slave_i : in nsl_axi.axi4_mm.master_t;
      slave_o : out nsl_axi.axi4_mm.slave_t;

      master_o : out nsl_axi.axi4_mm.master_t;
      master_i : in nsl_axi.axi4_mm.slave_t;
      
      rx_i : in nsl_axi.axi4_stream.master_t;
      rx_o : out nsl_axi.axi4_stream.slave_t;

      tx_o : out nsl_axi.axi4_stream.master_t;
      tx_i : in nsl_axi.axi4_stream.slave_t
      );
  end component;

end package;
