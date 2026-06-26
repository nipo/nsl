library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_bnoc, nsl_line_coding;

-- Bridge between a TCP socket (forwarded into the simulation by the GHDL
-- TCP-gateway plugin) and a bidirectional nsl_bnoc.framed interface, HDLC
-- framed on the wire.
--
-- Bytes received from the socket are HDLC-deframed and presented on rx_o;
-- frames presented on tx_i are HDLC-framed and sent back to the socket. So a
-- host program speaks HDLC-delimited frames over the TCP connection.
entity tcp_framed_gateway is
  generic(
    bind_port_c : natural
    );
  port(
    clock_i   : in std_ulogic;
    reset_n_i : in std_ulogic;

    -- Frames received from the TCP client.
    rx_o : out nsl_bnoc.framed.framed_req_t;
    rx_i : in  nsl_bnoc.framed.framed_ack_t;

    -- Frames to send to the TCP client.
    tx_i : in  nsl_bnoc.framed.framed_req_t;
    tx_o : out nsl_bnoc.framed.framed_ack_t
    );
end entity;

architecture beh of tcp_framed_gateway is

  constant cfg_c : nsl_amba.axi4_stream.config_t
    := nsl_amba.axi4_stream.config(1, last => false);

  signal tcp_rx_s, tcp_tx_s : nsl_amba.axi4_stream.bus_t;
  signal sock_rx_s, sock_tx_s : nsl_bnoc.pipe.pipe_bus_t;
  signal tx_clean_s : nsl_bnoc.framed.framed_req_t;

begin

  net: nsl_amba.stream_to_tcp.axi4_stream_tcp_gateway
    generic map(
      config_c => cfg_c,
      bind_port_c => bind_port_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      tx_i => tcp_tx_s.m,
      tx_o => tcp_tx_s.s,
      rx_o => tcp_rx_s.m,
      rx_i => tcp_rx_s.s
      );

  -- Socket bytes -> pipe.
  sock_rx_s.req <= nsl_bnoc.pipe.pipe_flit(
    data => nsl_amba.axi4_stream.bytes(cfg_c, tcp_rx_s.m)(0),
    valid => nsl_amba.axi4_stream.is_valid(cfg_c, tcp_rx_s.m));
  tcp_rx_s.s <= nsl_amba.axi4_stream.accept(cfg_c, sock_rx_s.ack.ready = '1');

  -- Pipe -> socket bytes.
  tcp_tx_s.m <= nsl_amba.axi4_stream.transfer(
    cfg_c,
    bytes => (0 => sock_tx_s.req.data),
    valid => sock_tx_s.req.valid = '1',
    last => false);
  sock_tx_s.ack.ready <= '1' when nsl_amba.axi4_stream.is_ready(cfg_c, tcp_tx_s.s) else '0';

  -- HDLC deframe: socket -> framed rx_o.
  deframer: nsl_line_coding.hdlc.hdlc_framed_unframer
    generic map(
      frame_max_size_c => 4096
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      hdlc_i => sock_rx_s.req,
      hdlc_o => sock_rx_s.ack,
      framed_o => rx_o,
      framed_i => rx_i
      );

  -- HDLC frame: framed tx_i -> socket. Resolve metavalues so they never reach
  -- the socket.
  tx_clean_s.data <= std_ulogic_vector(to_01(unsigned(tx_i.data)));
  tx_clean_s.valid <= tx_i.valid;
  tx_clean_s.last <= tx_i.last;

  framer: nsl_line_coding.hdlc.hdlc_framed_framer
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      framed_i => tx_clean_s,
      framed_o => tx_o,
      hdlc_o => sock_tx_s.req,
      hdlc_i => sock_tx_s.ack
      );

end architecture;
