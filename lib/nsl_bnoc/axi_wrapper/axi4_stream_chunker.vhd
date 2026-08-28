library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_bnoc, nsl_data;
use nsl_amba.axi4_stream.all;
use nsl_bnoc.framed.all;
use nsl_bnoc.axi_adapter.all;
use nsl_data.bytestream.all;

entity axi4_stream_chunker is
  generic(
    max_txn_length_l2_c : natural range 2 to 14 := 10;
    packet_config_c : config_t;
    chunks_config_c : config_t
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    packet_i : in master_t;
    packet_o : out slave_t;

    chunks_o : out master_t;
    chunks_i : in slave_t
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

architecture rtl of axi4_stream_chunker is

  signal framed_s: nsl_bnoc.framed.framed_bus_t;
  signal pipe_s: nsl_bnoc.pipe.pipe_bus_t;
  
begin

  framed_adapter: nsl_bnoc.axi_adapter.axi4_stream_to_framed
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      axi_i => packet_i,
      axi_o => packet_o,

      framed_o => framed_s.req,
      framed_i => framed_s.ack
      );

  chunker: nsl_bnoc.chunked_link.framed_chunker
    generic map(
      max_txn_length_l2_c => max_txn_length_l2_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      in_i => framed_s.req,
      in_o => framed_s.ack,

      out_o => pipe_s.req,
      out_i => pipe_s.ack
      );

  pipe_adapter: nsl_bnoc.axi_adapter.pipe_to_axi4_stream
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      pipe_i => pipe_s.req,
      pipe_o => pipe_s.ack,

      axi_o => chunks_o,
      axi_i => chunks_i
      );
  
end architecture;
