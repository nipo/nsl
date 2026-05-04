library ieee;
use ieee.std_logic_1164.all;

library nsl_amba, nsl_bnoc;
use nsl_amba.axi4_stream.all;
use nsl_bnoc.framed.all;
use nsl_bnoc.committed.all;
use nsl_bnoc.axi_adapter.all;

entity axi4_stream_to_committed is
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    axi_i : in master_t;
    axi_o : out slave_t;

    committed_o : out committed_req_t;
    committed_i : in committed_ack_t
    );
end entity;

architecture rtl of axi4_stream_to_committed is
  signal framed_s : framed_bus_t;
begin

  axi_to_framed: nsl_bnoc.axi_adapter.axi4_stream_to_framed
    port map(
      clock_i   => clock_i,
      reset_n_i => reset_n_i,

      axi_i => axi_i,
      axi_o => axi_o,

      framed_o => framed_s.req,
      framed_i => framed_s.ack
      );

  packetizer: nsl_bnoc.packetizer.committed_packetizer
    port map(
      clock_i   => clock_i,
      reset_n_i => reset_n_i,

      frame_valid_i => framed_s.req.valid,

      frame_i  => framed_s.req,
      frame_o  => framed_s.ack,

      packet_o => committed_o,
      packet_i => committed_i
      );

end architecture;
