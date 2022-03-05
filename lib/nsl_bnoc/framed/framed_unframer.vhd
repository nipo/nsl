library ieee;
use ieee.std_logic_1164.all;

library nsl_bnoc;
use nsl_bnoc.pipe.all;
use nsl_bnoc.framed.all;

entity framed_unframer is
  port(
    reset_n_i : in  std_ulogic;
    clock_i   : in  std_ulogic;

    frame_i  : in framed_req;
    frame_o  : out framed_ack;

    pipe_o   : out pipe_req_t;
    pipe_i   : in pipe_ack_t
    );
end entity;

architecture beh of framed_unframer is

begin

  pipe_o.data <= frame_i.data;
  pipe_o.valid <= frame_i.valid;
  frame_o.ready <= pipe_i.ready;

end architecture;
