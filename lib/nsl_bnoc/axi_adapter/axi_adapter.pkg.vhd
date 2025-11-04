library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_bnoc;
use nsl_amba.axi4_stream.all;

-- Adapters between BNOC (framed and pipe) and AXI4-Stream protocols
package axi_adapter is

  -- AXI4-Stream configuration matching BNOC framed abstraction:
  -- 1 byte data width, has last signal for frame boundaries
  constant axi4_stream_framed_config_c : config_t := config(bytes => 1, last => true);

  -- AXI4-Stream configuration matching BNOC pipe abstraction:
  -- 1 byte data width, no last signal (continuous stream)
  constant axi4_stream_pipe_config_c : config_t := config(bytes => 1, last => false);

  -- Convert BNOC framed to AXI4-Stream
  component framed_to_axi4_stream is
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      framed_i : in nsl_bnoc.framed.framed_req_t;
      framed_o : out nsl_bnoc.framed.framed_ack_t;

      axi_o : out master_t;
      axi_i : in slave_t
      );
  end component;

  -- Convert AXI4-Stream to BNOC framed
  component axi4_stream_to_framed is
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      axi_i : in master_t;
      axi_o : out slave_t;

      framed_o : out nsl_bnoc.framed.framed_req_t;
      framed_i : in nsl_bnoc.framed.framed_ack_t
      );
  end component;

  -- Convert BNOC pipe to AXI4-Stream
  component pipe_to_axi4_stream is
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      pipe_i : in nsl_bnoc.pipe.pipe_req_t;
      pipe_o : out nsl_bnoc.pipe.pipe_ack_t;

      axi_o : out master_t;
      axi_i : in slave_t
      );
  end component;

  -- Convert AXI4-Stream to BNOC pipe
  component axi4_stream_to_pipe is
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      axi_i : in master_t;
      axi_o : out slave_t;

      pipe_o : out nsl_bnoc.pipe.pipe_req_t;
      pipe_i : in nsl_bnoc.pipe.pipe_ack_t
      );
  end component;

end package;
