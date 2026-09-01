library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_math, work;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_math.int_ext.all;
use work.ipv4.all;

-- IPv4 layer over the AXI4-Stream transport conventions of
-- nsl_inet.stream.  Stacked on the ethernet layer through the 0x0800
-- ethertype pipe, it filters packets on destination address,
-- validates and consumes the IPv4 header, and dispatches packets on
-- protocol, one stream pair per handled protocol.
--
-- header_length_c lists the contents lengths of the blocks of the
-- layers below, forwarded verbatim in both directions.  Below, P
-- stands for nsl_inet.stream.context_byte_count(config_c,
-- header_length_c) and C for nsl_inet.stream.context_byte_count
-- (config_c, (0 => ip_context_length_c)).
--
-- Packets on the ethernet side
-- ============================
--
-- * Forwarded blocks [P]
-- * IPv4 header [20], beat aligned, no options
-- * Layer-4 PDU [*], possibly followed by mac padding on receive
--
-- Packets on the layer-4 side
-- ===========================
--
-- * Forwarded blocks [P], the same bytes as on the ethernet side
-- * Context block [C]: to_bytes(ip_context_t), tail padded
-- * Layer-4 PDU [*], trimmed to the length the IPv4 header declares
--
-- Receive rules
-- =============
--
-- Packets are dropped, without reaching any layer-4 pipe, when the
-- header checksum does not verify, the header carries options (IHL
-- above 5), the packet is a fragment, the destination address is
-- neither local_address_i nor the limited broadcast address, or the
-- protocol is not in the ip_proto_c table.  Multicast and subnet
-- broadcast are not supported.
--
-- The layer-4 PDU is trimmed to the total length the header
-- declares, removing mac padding.  A packet whose stream ends before
-- the declared length is forwarded with the reject flag set on its
-- last beat, as is a packet arriving already rejected.
--
-- Transmit rules
-- ==============
--
-- The header is crafted from the context: destination is peer,
-- source is local_address_i, protocol is the ip_proto_c entry of the
-- input pipe the packet came from, total length is the context
-- length plus the header size.  Packets are sent with the don't
-- fragment flag, an incrementing identification field, ttl_c as time
-- to live, and a header checksum computed at crafting time.  The
-- context casting field is ignored.  The layer does not pace nor
-- trim the payload: the layer-4 side must send exactly the context
-- length of PDU bytes.
package stream_ipv4 is

  constant ipv4_header_length_c : natural := 20;

  -- Context block produced and consumed by this layer.  Protocol
  -- does not appear here: streams above this layer exist after
  -- protocol dispatch, one per handled protocol.  Casting reports
  -- how the packet was addressed on receive and is ignored on
  -- transmit.  Length is the layer-4 PDU length in bytes: reported
  -- from the header on receive, used to craft the header on
  -- transmit.
  type ip_casting_t is (
    IP_CAST_UNICAST,
    IP_CAST_BROADCAST
    );

  type ip_context_t is
  record
    peer: ipv4_t;
    casting: ip_casting_t;
    length: integer range 0 to 65535;
  end record;

  constant ip_context_length_c: natural := 7;

  function to_bytes(ctx: ip_context_t) return byte_string;
  function from_bytes(data: byte_string) return ip_context_t;

  -- Pass-through trimming every packet to the length declared by a
  -- big-endian 16-bit field of the packet itself, found at byte
  -- offset length_offset_c.  The packet is cut at prefix_length_c
  -- plus the field value, but never before min_length_c: bytes
  -- beyond the cut are consumed and discarded.  The emitted last
  -- beat is withheld until the incoming last beat, so the reject
  -- flag of the trimmed tail is merged into it.  A packet ending
  -- before the cut point is forwarded with the reject flag set.
  --
  -- The input is never stalled beyond output-side backpressure.
  component stream_ipv4_trimmer is
    generic(
      config_c : config_t;
      length_offset_c : natural;
      prefix_length_c : natural;
      min_length_c : natural
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      in_i : in master_t;
      in_o : out slave_t;

      out_o : out master_t;
      out_i : in slave_t
      );
  end component;

  component stream_ipv4_receiver is
    generic(
      config_c : config_t;
      header_length_c : integer_vector := null_integer_vector;
      ip_proto_c : ip_proto_vector
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      local_address_i : in ipv4_t;

      in_i : in master_t;
      in_o : out slave_t;

      out_o : out master_vector(0 to ip_proto_c'length-1);
      out_i : in slave_vector(0 to ip_proto_c'length-1)
      );
  end component;

  component stream_ipv4_transmitter is
    generic(
      config_c : config_t;
      header_length_c : integer_vector := null_integer_vector;
      ip_proto_c : ip_proto_vector;
      ttl_c : integer range 0 to 255 := 64
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      local_address_i : in ipv4_t;

      in_i : in master_vector(0 to ip_proto_c'length-1);
      in_o : out slave_vector(0 to ip_proto_c'length-1);

      out_o : out master_t;
      out_i : in slave_t
      );
  end component;

  -- Union of the two components above, with one bidirectional stream
  -- pair per protocol.
  component stream_ipv4_layer is
    generic(
      config_c : config_t;
      header_length_c : integer_vector := null_integer_vector;
      ip_proto_c : ip_proto_vector;
      ttl_c : integer range 0 to 255 := 64
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      local_address_i : in ipv4_t;

      to_l4_o : out master_vector(0 to ip_proto_c'length-1);
      to_l4_i : in slave_vector(0 to ip_proto_c'length-1);
      from_l4_i : in master_vector(0 to ip_proto_c'length-1);
      from_l4_o : out slave_vector(0 to ip_proto_c'length-1);

      to_l3_o : out master_t;
      to_l3_i : in slave_t;
      from_l3_i : in master_t;
      from_l3_o : out slave_t
      );
  end component;

  -- ICMP echo responder, an endpoint for the ICMP protocol pipe of
  -- the IPv4 layer.  header_length_c lists every block preceding the
  -- ICMP PDU, the IPv4 context included; blocks are echoed verbatim
  -- into the reply, which reaches the requester through the context
  -- symmetry.
  --
  -- Echo requests are answered cut-through: the reply streams while
  -- the request is still being received, with the type rewritten and
  -- the checksum adjusted.  A request whose checksum does not verify,
  -- or arriving with the reject flag set, yields a reply with the
  -- reject flag set on its last beat.  ICMP messages other than echo
  -- requests are consumed silently.
  component stream_ipv4_icmp_echo is
    generic(
      config_c : config_t;
      header_length_c : integer_vector := null_integer_vector
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      in_i : in master_t;
      in_o : out slave_t;

      out_o : out master_t;
      out_i : in slave_t
      );
  end component;

end package;

package body stream_ipv4 is

  function to_bytes(ctx: ip_context_t) return byte_string
  is
    variable casting_v: byte;
  begin
    case ctx.casting is
      when IP_CAST_UNICAST =>
        casting_v := to_byte(0);
      when IP_CAST_BROADCAST =>
        casting_v := to_byte(1);
    end case;

    return ctx.peer & casting_v & to_be(to_unsigned(ctx.length, 16));
  end function;

  function from_bytes(data: byte_string) return ip_context_t
  is
    alias xd: byte_string(0 to ip_context_length_c-1) is data;
    variable ret: ip_context_t;
  begin
    assert data'length = ip_context_length_c
      report "Bad context block length"
      severity failure;

    ret.peer := xd(0 to 3);
    -- Unknown casting values read as unicast: the field is ignored
    -- on transmit and the receive side only emits values above.
    if xd(4) = to_byte(1) then
      ret.casting := IP_CAST_BROADCAST;
    else
      ret.casting := IP_CAST_UNICAST;
    end if;
    ret.length := to_integer(from_be(xd(5 to 6)));
    return ret;
  end function;

end package body;
