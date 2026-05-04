library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_bnoc;
use nsl_amba.axi4_stream.all;
use nsl_bnoc.committed.all;
use nsl_bnoc.framed.all;
use nsl_bnoc.axi_adapter.all;

entity committed_to_axi4_stream is
  generic(
    max_length_l2_c       : natural := 11;
    max_packet_count_l2_c : natural := 4
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    committed_i : in committed_req_t;
    committed_o : out committed_ack_t;

    axi_o : out master_t;
    axi_i : in slave_t
    );
end entity;

architecture rtl of committed_to_axi4_stream is
  signal framed_s: framed_bus_t;
begin

  unpacketizer: nsl_bnoc.packetizer.committed_unpacketizer_filter
    generic map(
      max_length_l2_c       => max_length_l2_c,
      max_packet_count_l2_c => max_packet_count_l2_c
      )
    port map(
      reset_n_i  => reset_n_i,
      clock_i(0) => clock_i,

      packet_i => committed_i,
      packet_o => committed_o,

      frame_o => framed_s.req,
      frame_i => framed_s.ack
      );

  framed_to_axi: nsl_bnoc.axi_adapter.framed_to_axi4_stream
    port map(
      clock_i   => clock_i,
      reset_n_i => reset_n_i,

      axi_o => axi_o,
      axi_i => axi_i,

      framed_i => framed_s.req,
      framed_o => framed_s.ack
      );

end architecture;
