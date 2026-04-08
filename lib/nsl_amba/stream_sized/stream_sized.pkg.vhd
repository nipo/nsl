library ieee;
use ieee.std_logic_1164.all;

library nsl_amba;

-- AXI4-Stream sized abstraction. A sized stream conveys frames
-- (i.e. data beats with a boundary marked by tlast) through a pipe
-- (a continuous stream interface without tlast). This is done by
-- adding a header between every frame with the following frame size.
--
-- Frame size is encoded as a 16-bit value, little endian, off by one
-- (size field of 0x0000 denotes a 1-byte frame).
package stream_sized is

  -- Reads a 2-byte size header (little endian, off by one) from the
  -- input stream (without tlast), then forwards the corresponding
  -- number of data bytes to the output stream, asserting tlast on
  -- the last byte.
  --
  -- out_config_c should have has_last set to true and data_width set to 1.
  component axi4_stream_sized_to_framed is
    generic(
      in_config_c : nsl_amba.axi4_stream.config_t;
      out_config_c : nsl_amba.axi4_stream.config_t
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      invalid_o : out std_ulogic;

      in_i : in nsl_amba.axi4_stream.master_t;
      in_o : out nsl_amba.axi4_stream.slave_t;

      out_o : out nsl_amba.axi4_stream.master_t;
      out_i : in nsl_amba.axi4_stream.slave_t
      );
  end component;

  -- Buffers a complete frame from the input stream (with tlast),
  -- then outputs a 2-byte size header (little endian, off by one)
  -- followed by the buffered data bytes on the output stream
  -- (without tlast).
  --
  -- in_config_c should have has_last set to true and data_width set to 1.
  -- max_txn_length_c must be at least 4 and no less than the maximum
  -- expected frame length.
  component axi4_stream_sized_from_framed is
    generic(
      in_config_c : nsl_amba.axi4_stream.config_t;
      out_config_c : nsl_amba.axi4_stream.config_t;
      max_txn_length_c : natural := 2048
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

end package stream_sized;
