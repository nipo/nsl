library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data;

package stream_crc is

  component axi4_stream_crc_adder is
    generic(
      config_c : nsl_amba.axi4_stream.config_t;
      crc_c : nsl_data.crc.crc_params_t
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      in_i : in nsl_amba.axi4_stream.master_t;
      in_o : out nsl_amba.axi4_stream.slave_t;

      out_o : out nsl_amba.axi4_stream.master_t;
      out_i : in nsl_amba.axi4_stream.slave_t
      );
  end component;

end package stream_crc;
