library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_logic, nsl_bnoc, work;
use nsl_data.bytestream.all;
use nsl_bnoc.committed.all;
use nsl_bnoc.pipe.all;
use nsl_bnoc.framed.all;
use work.hdlc.all;

entity hdlc_framed_framer is
  generic(
    stuff_c : boolean := false
    );
  port(
    clock_i     : in std_ulogic;
    reset_n_i   : in std_ulogic;

    framed_i : in framed_req;
    framed_o : out framed_ack;

    hdlc_o : out pipe_req_t;
    hdlc_i : in pipe_ack_t
    );
end entity;

architecture beh of hdlc_framed_framer is

  signal comm_s: committed_bus;
  constant header_c : byte_string(0 to 1) := (0 => to_byte(0),
                                              1 => control_u(pf => true, t => "00000"));

begin

  unframer: work.hdlc.hdlc_framer
    generic map(
      stuff_c => stuff_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      hdlc_i => hdlc_i,
      hdlc_o => hdlc_o,

      frame_o => comm_s.ack,
      frame_i => comm_s.req
      );

  pack: nsl_bnoc.packetizer.committed_packetizer
    generic map(
      header_length_c => 2
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i => clock_i,

      frame_header_i => header_c,

      packet_i => comm_s.ack,
      packet_o => comm_s.req,
      frame_o => framed_o,
      frame_i => framed_i
      );

end architecture;
