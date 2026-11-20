library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_bnoc, nsl_data;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;

-- USB CDC NCM (Network Control Model, NCM 1.0) data path.
--
-- An NCM function carries Ethernet frames, without FCS, packed in
-- Network Transfer Blocks (NTB): one NTB per USB bulk transfer, made of
-- an NTH16 header, the datagrams, and one or more NDP16 tables locating
-- them. This package converts between NTB16 streams (the bulk endpoint
-- side) and frame streams following the nsl_inet.stream conventions,
-- ready for nsl_inet.stream_host.stream_ipv4_host with l1_has_fcs_c
-- false: 1, 2 or 4 bytes per beat, packed keep, the front pad of
-- nsl_inet.stream_mac (2 bytes at width 4, none below) and the reject
-- flag (user bit 0 on the last beat) when the frame stream has a user
-- field. Descriptors and class requests belong to whatever runs the
-- control endpoint (nsl_usb.descriptor.cdc_functional_ncm and the
-- helpers below for the class request and notification payloads).
--
-- Only NTB16 is supported (no NTB32, no CRC mode).
package ncm is

  -- NTH16 / NDP16 signatures, in transmission order.
  constant ncm_nth16_signature_c : byte_string(0 to 3) := (x"4e", x"43", x"4d", x"48"); -- "NCMH"
  constant ncm_ndp16_signature_c : byte_string(0 to 3) := (x"4e", x"43", x"4d", x"30"); -- "NCM0"
  constant ncm_nth16_length_c : natural := 12;

  -- NCM class requests (NCM 1.0, 6.2) and notification codes (CDC 1.2,
  -- 6.3).
  constant NCM_REQUEST_SET_ETHERNET_PACKET_FILTER : natural := 16#43#;
  constant NCM_REQUEST_GET_NTB_PARAMETERS : natural := 16#80#;
  constant NCM_REQUEST_GET_NTB_FORMAT : natural := 16#83#;
  constant NCM_REQUEST_SET_NTB_FORMAT : natural := 16#84#;
  constant NCM_REQUEST_GET_NTB_INPUT_SIZE : natural := 16#85#;
  constant NCM_REQUEST_SET_NTB_INPUT_SIZE : natural := 16#86#;
  constant NCM_NOTIFICATION_NETWORK_CONNECTION : natural := 16#00#;
  constant NCM_NOTIFICATION_CONNECTION_SPEED_CHANGE : natural := 16#2a#;

  -- GET_NTB_PARAMETERS response (NCM 1.0, 6.2.1, 28 bytes), NTB16 only.
  -- ntb_in_max_size / ntb_out_max_size must match the ntb_max_size_c of
  -- the ncm_transmitter / ncm_receiver behind the function. Divisors and
  -- alignments are powers of two; 4 keeps datagrams and NDPs on 16-bit
  -- words.
  function ncm_ntb_parameters(
    ntb_in_max_size, ntb_out_max_size : positive;
    in_divisor, out_divisor : positive := 4;
    in_payload_remainder, out_payload_remainder : natural := 0;
    in_alignment, out_alignment : positive := 4;
    out_max_datagrams : natural := 0)
    return byte_string;

  -- Interrupt IN notifications of the communication interface:
  -- NETWORK_CONNECTION (8 bytes) and CONNECTION_SPEED_CHANGE (16 bytes),
  -- bit rates in bit/s.
  function ncm_network_connection(
    interface : natural;
    connected : boolean)
    return byte_string;

  function ncm_connection_speed_change(
    interface : natural;
    downstream_bitrate, upstream_bitrate : natural)
    return byte_string;

  type ncm_receiver_stats_t is
  record
    -- NTBs accepted (valid NTH16), datagrams delivered
    ntb_count : unsigned(31 downto 0);
    datagram_count : unsigned(31 downto 0);
    -- Header resynchronizations, NTBs with an invalid NDP16 chain,
    -- datagram entries skipped (out of the NTB, shorter than an
    -- ethernet header, longer than datagram_max_size_c)
    header_error_count : unsigned(31 downto 0);
    ndp_error_count : unsigned(31 downto 0);
    datagram_error_count : unsigned(31 downto 0);
  end record;

  type ncm_transmitter_stats_t is
  record
    ntb_count : unsigned(31 downto 0);
    datagram_count : unsigned(31 downto 0);
    -- Frames dropped: flagged rejected, shorter than an ethernet header
    -- or longer than datagram_max_size_c
    drop_count : unsigned(31 downto 0);
  end record;

  -- NTB16 stream to frames (host -> device).
  --
  -- ntb_i carries NTB16 blocks, 1 or 2 bytes per beat (ntb_config_c;
  -- last is ignored). Each block is framed by the wBlockLength of its
  -- header, so the stream needs no transfer boundaries (e.g. an FX2 in
  -- AUTOOUT mode). Every block starts on a beat boundary: the bytes left
  -- in the beat that ends a block are discarded (the padding byte of an
  -- odd-length transfer on a 16-bit bus).
  --
  -- A whole block is stored (two buffers of ntb_max_size_c bytes) before
  -- its NDP16 chain is walked, so NDPs and datagrams may come in any
  -- order (Linux puts the NDP first, ndp_to_end last), while the next
  -- block is received. Datagrams come out on frame_o (frame_config_c, 1,
  -- 2 or 4 bytes per beat, keep required above 1, last), one frame per
  -- datagram, whatever its offset in the block. At 4 bytes, each frame
  -- starts with 2 zero bytes of front pad. The reject flag is driven low:
  -- no frame is delivered rejected.
  --
  -- A bad header counts a header error and the receiver scans the
  -- following beats for the next "NCMH". Bad NDPs and datagram entries
  -- are counted and skipped.
  component ncm_receiver is
    generic(
      ntb_config_c : config_t;
      frame_config_c : config_t;
      ntb_max_size_c : positive := 16384;
      datagram_max_size_c : positive := 1514
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      ntb_i : in master_t;
      ntb_o : out slave_t;

      frame_o : out master_t;
      frame_i : in slave_t;

      stats_o : out ncm_receiver_stats_t
      );
  end component;

  -- Frames to NTB16 stream (device -> host).
  --
  -- frame_i carries frames (frame_config_c, 1, 2 or 4 bytes per beat,
  -- keep required above 1, last). At 4 bytes, the 2-byte front pad of
  -- each frame is skipped, and a beat is taken in two cycles. A frame
  -- flagged rejected (user bit 0 on the last beat, nsl_inet.stream
  -- convention, when frame_config_c has a user field) is dropped.
  --
  -- Frames are packed in NTB16 blocks in two buffers of ntb_max_size_c
  -- bytes: NTH16, datagrams on 4-byte boundaries, NDP16 last. A block is
  -- closed when no frame is waiting and the other buffer is free (one
  -- frame per block at light load, more under load), when the next frame
  -- might not fit, or after datagram_max_count_c frames. Blocks go out on
  -- ntb_o (ntb_config_c, 1 or 2 bytes per beat), tlast on the last beat:
  -- one USB transfer per block.
  --
  -- With zlp_avoid_size_c non zero, a block whose length is a multiple of
  -- it gets 4 padding bytes, so it ends with a short packet: for
  -- endpoints that cannot send a zero-length packet themselves. Use the
  -- full-speed packet size (64), which covers high speed too. 0 for
  -- endpoints that end transfers on their own (nsl_usb
  -- device_ep_framed_in).
  component ncm_transmitter is
    generic(
      frame_config_c : config_t;
      ntb_config_c : config_t;
      ntb_max_size_c : positive := 16384;
      datagram_max_size_c : positive := 1514;
      datagram_max_count_c : positive := 32;
      zlp_avoid_size_c : natural := 64
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      frame_i : in master_t;
      frame_o : out slave_t;

      ntb_o : out master_t;
      ntb_i : in slave_t;

      stats_o : out ncm_transmitter_stats_t
      );
  end component;

  -- ncm_receiver with bnoc ports: NTB16 bytes from a pipe (e.g.
  -- nsl_usb.device.device_ep_bulk_out), frames as committed packets
  -- (always valid), e.g. for nsl_inet.func.ethernet_host with
  -- l1_has_fcs_c false.
  component ncm_receiver_bnoc is
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
  end component;

  -- ncm_transmitter with bnoc ports: frames as committed packets (invalid
  -- ones are dropped), NTB16 blocks as framed frames, one per block (e.g.
  -- nsl_usb.device.device_ep_framed_in, which ends the transfer, short
  -- packet or ZLP, on its own: zlp_avoid_size_c defaults to 0 here).
  component ncm_transmitter_bnoc is
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
  end component;

end package;

package body ncm is

  function le16(v : natural) return byte_string
  is
  begin
    return nsl_data.endian.to_le(to_unsigned(v, 16));
  end function;

  function le32(v : natural) return byte_string
  is
  begin
    return nsl_data.endian.to_le(to_unsigned(v, 32));
  end function;

  function ncm_ntb_parameters(
    ntb_in_max_size, ntb_out_max_size : positive;
    in_divisor, out_divisor : positive := 4;
    in_payload_remainder, out_payload_remainder : natural := 0;
    in_alignment, out_alignment : positive := 4;
    out_max_datagrams : natural := 0)
    return byte_string
  is
    constant ret : byte_string(0 to 27)
      := le16(28)                       -- wLength
      & le16(1)                         -- bmNtbFormatsSupported: NTB16
      & le32(ntb_in_max_size)
      & le16(in_divisor)
      & le16(in_payload_remainder)
      & le16(in_alignment)
      & le16(0)                         -- reserved
      & le32(ntb_out_max_size)
      & le16(out_divisor)
      & le16(out_payload_remainder)
      & le16(out_alignment)
      & le16(out_max_datagrams);
  begin
    return ret;
  end function;

  function notification_header(
    code, value, interface, length : natural)
    return byte_string
  is
  begin
    return byte_string'(0 => x"a1")    -- class, interface, device to host
      & to_byte(code)
      & le16(value)
      & le16(interface)
      & le16(length);
  end function;

  function ncm_network_connection(
    interface : natural;
    connected : boolean)
    return byte_string
  is
    variable value : natural := 0;
  begin
    if connected then
      value := 1;
    end if;
    return notification_header(NCM_NOTIFICATION_NETWORK_CONNECTION,
                               value, interface, 0);
  end function;

  function ncm_connection_speed_change(
    interface : natural;
    downstream_bitrate, upstream_bitrate : natural)
    return byte_string
  is
    constant ret : byte_string(0 to 15)
      := notification_header(NCM_NOTIFICATION_CONNECTION_SPEED_CHANGE,
                             0, interface, 8)
      & le32(downstream_bitrate)
      & le32(upstream_bitrate);
  begin
    return ret;
  end function;

end package body;
