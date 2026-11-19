library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_bnoc, nsl_math, nsl_usb;
use nsl_amba.axi4_stream.all;
use nsl_bnoc.axi_adapter.all;
use nsl_usb.ncm.all;

entity ncm_transmitter_bnoc is
  generic(
    ntb_max_size_c : positive := 16384;
    datagram_max_size_c : positive := 1514;
    datagram_max_count_c : positive := 32;
    zlp_avoid_size_c : natural := 0
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    frame_i : in nsl_bnoc.committed.committed_req_t;
    frame_o : out nsl_bnoc.committed.committed_ack_t;

    ntb_o : out nsl_bnoc.framed.framed_req_t;
    ntb_i : in nsl_bnoc.framed.framed_ack_t;

    stats_o : out ncm_transmitter_stats_t
    );
end entity;

architecture beh of ncm_transmitter_bnoc is

  signal ntb_s, frame_s : bus_t;

begin

  -- Buffers each frame and drops the invalid ones.
  to_axi: nsl_bnoc.axi_adapter.committed_to_axi4_stream
    generic map(
      max_length_l2_c => nsl_math.arith.log2(datagram_max_size_c + 1)
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      committed_i => frame_i,
      committed_o => frame_o,
      axi_o => frame_s.m,
      axi_i => frame_s.s
      );

  transmitter: nsl_usb.ncm.ncm_transmitter
    generic map(
      frame_config_c => axi4_stream_committed_config_c,
      ntb_config_c => axi4_stream_framed_config_c,
      ntb_max_size_c => ntb_max_size_c,
      datagram_max_size_c => datagram_max_size_c,
      datagram_max_count_c => datagram_max_count_c,
      zlp_avoid_size_c => zlp_avoid_size_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      frame_i => frame_s.m,
      frame_o => frame_s.s,
      ntb_o => ntb_s.m,
      ntb_i => ntb_s.s,
      stats_o => stats_o
      );

  to_framed: nsl_bnoc.axi_adapter.axi4_stream_to_framed
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      axi_i => ntb_s.m,
      axi_o => ntb_s.s,
      framed_o => ntb_o,
      framed_i => ntb_i
      );

end architecture;
