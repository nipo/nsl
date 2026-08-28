library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_bnoc, nsl_data;
use nsl_amba.axi4_stream.all;
use nsl_bnoc.framed.all;
use nsl_bnoc.axi_adapter.all;
use nsl_data.bytestream.all;

entity axi4_stream_unchunker is
  generic(
    packet_config_c : config_t;
    chunks_config_c : config_t
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    chunks_i : in master_t;
    chunks_o : out slave_t;

    packet_o : out master_t;
    packet_i : in slave_t;

    reset_n_o : out std_ulogic
    );
begin

  assert packet_config_c.data_width = 1
    report "Packet config can only be 1 byte in width"
    severity failure;

  assert chunks_config_c.data_width = 1
    report "Packet config can only be 1 byte in width"
    severity failure;

  assert packet_config_c.has_last
    report "Packet config must be framed"
    severity failure;

end entity;

architecture rtl of axi4_stream_unchunker is

  signal pipe_s: nsl_bnoc.pipe.pipe_bus_t;
  signal framed_s: nsl_bnoc.framed.framed_bus_t;
  
begin

  pipe_adapter: nsl_bnoc.axi_adapter.axi4_stream_to_pipe
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      axi_i => chunks_i,
      axi_o => chunks_o,

      pipe_o => pipe_s.req,
      pipe_i => pipe_s.ack
      );

  unchunker: nsl_bnoc.chunked_link.framed_unchunker
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      in_i => pipe_s.req,
      in_o => pipe_s.ack,

      out_o => framed_s.req,
      out_i => framed_s.ack,

      reset_n_o => reset_n_o
      );

  framed_adapter: nsl_bnoc.axi_adapter.framed_to_axi4_stream
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      framed_i => framed_s.req,
      framed_o => framed_s.ack,

      axi_o => packet_o,
      axi_i => packet_i
      );
  
end architecture;
