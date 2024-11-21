library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_logic, nsl_bnoc, work;
use nsl_bnoc.pipe.all;
use nsl_bnoc.framed.all;
use nsl_bnoc.committed.all;
use work.hdlc.all;

entity hdlc_framed_unframer is
  generic(
    frame_max_size_c: natural := 512
    );
  port(
    clock_i     : in std_ulogic;
    reset_n_i   : in std_ulogic;

    hdlc_i : in nsl_bnoc.pipe.pipe_req_t;
    hdlc_o : out nsl_bnoc.pipe.pipe_ack_t;

    framed_o : out nsl_bnoc.framed.framed_req;
    framed_i : in nsl_bnoc.framed.framed_ack
    );
end entity;

architecture beh of hdlc_framed_unframer is

  signal comm_s, filt_s: committed_bus;
  
begin

  unframer: work.hdlc.hdlc_unframer
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      hdlc_i => hdlc_i,
      hdlc_o => hdlc_o,

      frame_o => comm_s.req,
      frame_i => comm_s.ack
      );

  filter: nsl_bnoc.committed.committed_filter
    port map(
      reset_n_i => reset_n_i,
      clock_i => clock_i,

      in_i => comm_s.req,
      in_o => comm_s.ack,

      out_o => filt_s.req,
      out_i => filt_s.ack
      );
  
  unpack: nsl_bnoc.packetizer.committed_unpacketizer
    generic map(
      header_length_c => 2
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i => clock_i,

      packet_i => filt_s.req,
      packet_o => filt_s.ack,
      frame_o => framed_o,
      frame_i => framed_i
      );

end architecture;
