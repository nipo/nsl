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

  -- Able to validate packet CRC in-stream. The error_in pin can also be used to force CRC invalid.
  component axi4_stream_crc_checker is
    generic (
        config_c : nsl_amba.axi4_stream.config_t;
        crc_c    : nsl_data.crc.crc_params_t
    );
    port (
        clock_i   : in std_ulogic;
        reset_n_i : in std_ulogic;

        in_i : in  nsl_amba.axi4_stream.master_t;
        in_o : out nsl_amba.axi4_stream.slave_t;
        in_error_i : in std_ulogic := '0';

        out_o : out nsl_amba.axi4_stream.master_t;
        out_i : in  nsl_amba.axi4_stream.slave_t;

        crc_valid_o : out std_ulogic
    );
  end component;

end package stream_crc;
