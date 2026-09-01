library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_math, work;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_math.int_ext.all;
use work.ipv4.all;

-- UDP layer over the AXI4-Stream transport conventions of
-- nsl_inet.stream.  Stacked on the IPv4 layer's UDP protocol pipe,
-- it validates and consumes the UDP header and dispatches datagrams
-- on destination port, one stream pair per entry of the udp_port_c
-- table.
--
-- This layer is a sibling of the IPv4 layer: the last block listed
-- in header_length_c must be the IPv4 context, which it reads for
-- the checksum pseudo-header and for the datagram length, and
-- forwards untouched like every other block.  Below, P stands for
-- nsl_inet.stream.context_byte_count(config_c, header_length_c) and
-- C for nsl_inet.stream.context_byte_count(config_c,
-- (0 => udp_context_length_c)).
--
-- Packets on the IPv4 side
-- ========================
--
-- * Forwarded blocks [P], ending with the IPv4 context block
-- * UDP header [8], beat aligned
-- * Payload [*]
--
-- Packets on the application side
-- ===============================
--
-- * Forwarded blocks [P], the same bytes as on the IPv4 side
-- * Context block [C]: to_bytes(udp_context_t), tail padded
-- * Payload [*], exactly the datagram payload
--
-- Receive rules
-- =============
--
-- Datagrams are dropped when the UDP length does not match the
-- length the IPv4 context declares, or when the destination port is
-- not in the udp_port_c table.  When the checksum field is non-zero,
-- the internet checksum over the pseudo-header, the UDP header and
-- the payload is verified; as the verdict is only known at the last
-- beat, a failing datagram is forwarded with the reject flag set.
-- A datagram arriving rejected stays rejected.
--
-- Transmit rules
-- ==============
--
-- The header is crafted from the pipe and the context: source port
-- is the udp_port_c entry of the input pipe, destination port is
-- the context peer port, length is taken from the IPv4 context
-- block, which the application must set to eight plus the payload
-- length.  The checksum field is sent as zero, which IPv4 permits;
-- checksum generation on transmit is not implemented.
package stream_udp is

  constant udp_header_length_c : natural := 8;

  -- Context block produced and consumed by this layer.  Local port
  -- does not appear: streams exist after port dispatch.  The peer
  -- port is the datagram source port on receive and the destination
  -- port on transmit.
  type udp_context_t is
  record
    peer_port: integer range 0 to 65535;
  end record;

  constant udp_context_length_c: natural := 2;

  function to_bytes(ctx: udp_context_t) return byte_string;
  function from_bytes(data: byte_string) return udp_context_t;

  -- Pass-through verifying the UDP checksum of every datagram on
  -- the IPv4 side layout, from the pseudo-header fields read at
  -- constant offsets and local_address_i.  Datagrams with a zero
  -- checksum field pass unverified.  Failing datagrams get the
  -- reject flag on their last beat; an incoming reject flag is
  -- preserved.
  component stream_udp_validator is
    generic(
      config_c : config_t;
      header_length_c : integer_vector := null_integer_vector
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      local_address_i : in ipv4_t;

      in_i : in master_t;
      in_o : out slave_t;

      out_o : out master_t;
      out_i : in slave_t
      );
  end component;

  component stream_udp_receiver is
    generic(
      config_c : config_t;
      header_length_c : integer_vector := null_integer_vector;
      udp_port_c : integer_vector
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      local_address_i : in ipv4_t;

      in_i : in master_t;
      in_o : out slave_t;

      out_o : out master_vector(0 to udp_port_c'length-1);
      out_i : in slave_vector(0 to udp_port_c'length-1)
      );
  end component;

  component stream_udp_transmitter is
    generic(
      config_c : config_t;
      header_length_c : integer_vector := null_integer_vector;
      udp_port_c : integer_vector
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      in_i : in master_vector(0 to udp_port_c'length-1);
      in_o : out slave_vector(0 to udp_port_c'length-1);

      out_o : out master_t;
      out_i : in slave_t
      );
  end component;

  -- Union of the two components above, with one bidirectional stream
  -- pair per port.
  component stream_udp_layer is
    generic(
      config_c : config_t;
      header_length_c : integer_vector := null_integer_vector;
      udp_port_c : integer_vector
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      local_address_i : in ipv4_t;

      to_app_o : out master_vector(0 to udp_port_c'length-1);
      to_app_i : in slave_vector(0 to udp_port_c'length-1);
      from_app_i : in master_vector(0 to udp_port_c'length-1);
      from_app_o : out slave_vector(0 to udp_port_c'length-1);

      to_l4_o : out master_t;
      to_l4_i : in slave_t;
      from_l4_i : in master_t;
      from_l4_o : out slave_t
      );
  end component;

end package;

package body stream_udp is

  function to_bytes(ctx: udp_context_t) return byte_string
  is
  begin
    return to_be(to_unsigned(ctx.peer_port, 16));
  end function;

  function from_bytes(data: byte_string) return udp_context_t
  is
    alias xd: byte_string(0 to udp_context_length_c-1) is data;
    variable ret: udp_context_t;
  begin
    assert data'length = udp_context_length_c
      report "Bad context block length"
      severity failure;

    ret.peer_port := to_integer(from_be(xd(0 to 1)));
    return ret;
  end function;

end package body;
