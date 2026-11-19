library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_bnoc, nsl_usb;
use nsl_amba.axi4_stream.all;
use nsl_bnoc.axi_adapter.all;
use nsl_usb.ncm.all;

entity ncm_receiver_bnoc is
  generic(
    ntb_max_size_c : positive := 16384;
    datagram_max_size_c : positive := 1514
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    ntb_i : in nsl_bnoc.pipe.pipe_req_t;
    ntb_o : out nsl_bnoc.pipe.pipe_ack_t;

    frame_o : out nsl_bnoc.committed.committed_req_t;
    frame_i : in nsl_bnoc.committed.committed_ack_t;

    stats_o : out ncm_receiver_stats_t
    );
end entity;

architecture beh of ncm_receiver_bnoc is

  signal ntb_s, frame_s : bus_t;

begin

  to_axi: nsl_bnoc.axi_adapter.pipe_to_axi4_stream
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      pipe_i => ntb_i,
      pipe_o => ntb_o,
      axi_o => ntb_s.m,
      axi_i => ntb_s.s
      );

  receiver: nsl_usb.ncm.ncm_receiver
    generic map(
      ntb_config_c => axi4_stream_pipe_config_c,
      frame_config_c => axi4_stream_committed_config_c,
      ntb_max_size_c => ntb_max_size_c,
      datagram_max_size_c => datagram_max_size_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      ntb_i => ntb_s.m,
      ntb_o => ntb_s.s,
      frame_o => frame_s.m,
      frame_i => frame_s.s,
      stats_o => stats_o
      );

  -- Every frame out of the receiver is valid.
  to_committed: nsl_bnoc.axi_adapter.axi4_stream_to_committed
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      axi_i => frame_s.m,
      axi_o => frame_s.s,
      committed_o => frame_o,
      committed_i => frame_i
      );

end architecture;
