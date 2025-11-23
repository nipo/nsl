library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_data, work;
use nsl_bnoc.committed.all;
use nsl_bnoc.framed.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.text.all;
use work.checksum.all;

-- IPv4 is a layer-3 protocol, it requires ICMP to function
-- correctly, ICMP is layer-4. Both are defined here.
package ipv4 is

  -- IPv4 address, in network order
  --@-- convert python:str, serialize:'value', convert:nsl_inet.ipv4.to_ipv4({})
  subtype ipv4_t is byte_string(0 to 3);

  subtype ipv4_nibble_t is integer range 0 to 255;
  function to_ipv4(a, b, c, d: ipv4_nibble_t) return ipv4_t;
  function to_ipv4(s: string) return ipv4_t;
  function ip_to_string(ip: ipv4_t) return string;

  subtype ip_proto_t is integer range 0 to 255;
  type ip_proto_vector is array(natural range <>) of ip_proto_t;
  constant ip_proto_vector_null_c: ip_proto_vector(0 to -1) := (others => 0);

  subtype ip_packet_id_t is unsigned(15 downto 0);

  constant ip_proto_icmp : ip_proto_t := 1;
  constant ip_proto_tcp  : ip_proto_t := 6;
  constant ip_proto_udp  : ip_proto_t := 17;
  constant ip_proto_gre  : ip_proto_t := 47;

  function vector_contains(v: ip_proto_vector; p: ip_proto_t) return boolean;
  
  -- Peer IP, Context
  constant ipv4_layer_header_length_c : natural := 5;
  -- Peer IP, Context, Proto
  constant ipv4_trx_header_length_c : natural := 6;

  -- Frame structure form/to layer 2:
  -- * Header of fixed length, passed through [N]
  -- * IP header [20+]
  -- * L4 PDU
  -- * Padding (on RX)
  -- * Status byte
  --   [0] = validity bit

  -- Frame structure from/to layer 4
  -- * Header of fixed length, passed through [N]
  -- * Peer IP address [4]
  -- * Packet source/destination context
  --   [0] Address type (0: Unicast, 1: Broadcast)
  --   [7:1] Reserved
  -- * Protocol number (ip_proto_t) [1]
  -- * Layer 4 PDU size, big endian [2]
  -- * Layer 4 PDU
  -- * Status
  --   [0]   Validity bit
  --   [7:1] Reserved

  -- Fragmentation is not handled. Fragmented packets are classified
  -- as invalid (i.e. fragment offset must be 0, total length must be
  -- at most frame length).
  
  -- This component can detect its own unicast address or broadcast
  -- address. Multicast is not supported.
  component ipv4_receiver is
    generic(
      -- Flit count to drop at the start of a frame Sum of L1 and L2
      -- header lengths
      header_length_c : integer
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      unicast_i : in ipv4_t;
      broadcast_i : in ipv4_t;

      l2_i : in committed_req;
      l2_o : out committed_ack;

      l4_o : out committed_req;
      l4_i : in committed_ack
      );
  end component;

  component ipv4_transmitter is
    generic(
      ttl_c : integer := 64;
      header_length_c : integer
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      unicast_i : in ipv4_t;

      -- From layer 4+
      l4_i : in committed_req;
      l4_o : out committed_ack;

      -- To layer 2
      l2_o : out committed_req;
      l2_i : in committed_ack
      );
  end component;

  -- This module is meant to be inserted between IP layer and its
  -- parent.  This module rewrites IP/TCP/UDP/ICMP headers to
  -- implement checksumming with minimal delay.  IP and ICMP are
  -- mandatory.  UDP and TCP handling is optional.
  --
  -- Frame structure:
  -- * Header of fixed length, passed through [N]
  -- * IP header [20+]
  -- * L4 PDU (ICMP, TCP, UDP)
  -- * Status byte
  --   [0] = validity bit
  component ipv4_checksum_inserter is
    generic(
      header_length_c : integer;
      mtu_c: integer := 1500;
      handle_tcp_c: boolean := true;
      handle_udp_c: boolean := true
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      -- IPv4 packet input
      input_i : in committed_req;
      input_o : out committed_ack;

      -- IPv4 packet output
      output_o : out committed_req;
      output_i : in committed_ack
      );
  end component;

  -- Meant to be stacked on IPv4
  -- Able to respond to ICMP echo requests (Ping)
  component icmpv4 is
    generic(
      -- Including IPv4 header part
      header_length_c : natural
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      -- To IPv4, without ip protocol byte
      to_l3_o : out committed_req;
      to_l3_i : in committed_ack;
      from_l3_i : in committed_req;
      from_l3_o : out committed_ack

      -- Ping request/response API (TBD)
      -- Contents:
      -- * peer IP (network order) [4]
      -- * identifier (network order) [2]
      -- * sequence no (network order) [2]
      -- * more data [N]
      -- * commit [1].
      -- ping_request_i : in committed_req := committed_req_idle_c;
      -- ping_request_o : out committed_ack;
      -- ping_response_o : out committed_req;
      -- ping_response_i : in committed_ack := committed_ack_idle_c

      -- Error stream to TCP
      -- TBD

      -- Error stream to UDP
      -- TBD
      );
  end component;

  -- Contains IPv4 tx/rx, ICMPv4, protocol dispatcher
  --
  -- ip_proto_c may not contain ICMP.
  component ipv4_layer is
    generic(
      header_length_c : integer := 0;
      ttl_c : integer := 64;
      ip_proto_c : ip_proto_vector;
      mtu_c: integer := 1500
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      unicast_i : in ipv4_t;
      broadcast_i : in ipv4_t;

      -- Layer 4 IOs
      to_l4_o : out committed_req_array(0 to ip_proto_c'length-1);
      to_l4_i : in committed_ack_array(0 to ip_proto_c'length-1);
      from_l4_i : in committed_req_array(0 to ip_proto_c'length-1);
      from_l4_o : out committed_ack_array(0 to ip_proto_c'length-1);

      -- Layer 2 IO
      to_l2_o : out committed_req;
      to_l2_i : in committed_ack;
      from_l2_i : in committed_req;
      from_l2_o : out committed_ack
      );
  end component;

  -- IP Header
  -- [ 0- 3] Version/Len  TOS     Total len
  -- [ 4- 7] Identification       Frag offset
  -- [ 8-11] TTL      Proto       Chksum
  -- [12-15] SRC Addr
  -- [16-19] DST Addr
  -- [20+  ] Opts.

  constant ip_off_type_len : integer := 0;
  constant ip_off_tos      : integer := 1;
  constant ip_off_len_h    : integer := 2;
  constant ip_off_len_l    : integer := 3;
  constant ip_off_id_h     : integer := 4;
  constant ip_off_id_l     : integer := 5;
  constant ip_off_off_h    : integer := 6;
  constant ip_off_off_l    : integer := 7;
  constant ip_off_ttl      : integer := 8;
  constant ip_off_proto    : integer := 9;
  constant ip_off_chk_h    : integer := 10;
  constant ip_off_chk_l    : integer := 11;
  constant ip_off_src0     : integer := 12;
  constant ip_off_src1     : integer := 13;
  constant ip_off_src2     : integer := 14;
  constant ip_off_src3     : integer := 15;
  constant ip_off_dst0     : integer := 16;
  constant ip_off_dst1     : integer := 17;
  constant ip_off_dst2     : integer := 18;
  constant ip_off_dst3     : integer := 19;

  function ipv4_pack(
    destination, source : ipv4_t;
    proto : ip_proto_t;
    data : byte_string;
    id : ip_packet_id_t := x"0000";
    ttl : integer := 64) return byte_string;
  function ipv4_is_header_valid(
    datagram : byte_string) return boolean;

  function icmpv4_pack(
    typ, code : integer;
    header : byte_string(0 to 3) := (others => x"00");
    data : byte_string := null_byte_string)
    return byte_string;
  function icmpv4_echo_request_pack(
    identifier, sequence : integer;
    data : byte_string := null_byte_string)
    return byte_string;

  function ipv4_len_get(packet: byte_string) return integer;
  function ipv4_source_get(packet: byte_string) return ipv4_t;
  function ipv4_destination_get(packet: byte_string) return ipv4_t;
  function ipv4_proto_get(packet: byte_string) return ip_proto_t;
  function ipv4_ihl_bytes_get(packet: byte_string) return integer;
  function ipv4_data_get(packet: byte_string) return byte_stream;
  function ipv4_data_get(packet: byte_string) return byte_string;
  
end package;

package body ipv4 is

  function to_ipv4(a, b, c, d: ipv4_nibble_t) return ipv4_t
  is
    variable ret : ipv4_t;
  begin
    ret(0) := to_byte(a);
    ret(1) := to_byte(b);
    ret(2) := to_byte(c);
    ret(3) := to_byte(d);
    return ret;
  end function;

  function ipv4_pack(
    destination, source : ipv4_t;
    proto : ip_proto_t;
    data : byte_string;
    id : ip_packet_id_t := x"0000";
    ttl : integer := 64) return byte_string
  is
    variable header : byte_string(0 to 19) := (others => x"00");
    variable chk : checksum_acc_t := checksum_acc_init_c;
  begin
    header(ip_off_type_len) := x"45";
    header(ip_off_len_h to ip_off_len_l) := to_be(to_unsigned(header'length + data'length, 16));
    header(ip_off_id_h to ip_off_id_l) := to_be(id);
    header(ip_off_ttl) := to_byte(ttl);
    header(ip_off_proto) := to_byte(proto);
    header(ip_off_src0 to ip_off_src3) := source;
    header(ip_off_dst0 to ip_off_dst3) := destination;

    chk := checksum_update(chk, header);
    header(ip_off_chk_h to ip_off_chk_l) := checksum_spill(chk);

    return header & data;
  end function;

  function ipv4_is_header_valid(
    datagram : byte_string) return boolean
  is
    alias xd: byte_string(0 to datagram'length-1) is datagram;
    variable header_size : integer;
    variable chk : checksum_acc_t := checksum_acc_init_c;
  begin
    header_size := to_integer(unsigned(xd(ip_off_type_len)(4 downto 0)));
    if header_size < 5 then
      return false;
    end if;

    header_size := header_size * 4;
    if xd'length < header_size then
      return false;
    end if;

    return checksum_is_valid(xd(0 to header_size - 1));
  end function;

  function ip_to_string(ip: ipv4_t) return string
  is
  begin
    return to_string(to_integer(ip(0)))
      & "." & to_string(to_integer(ip(1)))
      & "." & to_string(to_integer(ip(2)))
      & "." & to_string(to_integer(ip(3)));
  end function;

  function icmpv4_pack(
    typ, code : integer;
    header : byte_string(0 to 3) := (others => x"00");
    data : byte_string := null_byte_string)
    return byte_string
  is
    variable hdr: byte_string(0 to 7) := (others => x"00");
    variable chk : checksum_acc_t := checksum_acc_init_c;
  begin
    hdr(0) := to_byte(typ);
    hdr(1) := to_byte(code);
    hdr(4 to 7) := header;

    chk := checksum_update(chk, hdr);
    chk := checksum_update(chk, data);

    hdr(2 to 3) := checksum_spill(chk, data'length mod 2 = 1);

    return hdr & data;
  end function;
    
  function icmpv4_echo_request_pack(
    identifier, sequence : integer;
    data : byte_string := null_byte_string)
    return byte_string
  is
  begin
    return icmpv4_pack(8, 0,
                       to_be(to_unsigned(identifier, 16))
                       &  to_be(to_unsigned(sequence, 16)),
                       data);
  end function;

  function vector_contains(v: ip_proto_vector; p: ip_proto_t) return boolean
  is
  begin
    for i in v'range
    loop
      if v(i) = p then
        return true;
      end if;
    end loop;
    return false;
  end function;

  function to_ipv4(s: string) return ipv4_t
  is
    alias xs: string(1 to s'length) is s;
    variable r: ipv4_t;
    variable start, stop: integer;
  begin
    start := 0;

    for i in r'range
    loop
      stop := strchr(xs, '.', start);
      if stop = -1 then
        stop := xs'right;
      end if;
      r(i) := to_byte(strtoi(xs(1+start to stop)));
      start := stop + 1;
    end loop;

    return r;
  end function;

  function ipv4_len_get(packet: byte_string) return integer
  is
    alias xp: byte_string(0 to packet'length-1) is packet;
  begin
    return to_integer(from_be(xp(ip_off_len_h to ip_off_len_l)));
  end function;

  function ipv4_source_get(packet: byte_string) return ipv4_t
  is
    alias xp: byte_string(0 to packet'length-1) is packet;
  begin
    return xp(ip_off_src0 to ip_off_src3);
  end function;

  function ipv4_destination_get(packet: byte_string) return ipv4_t
  is
    alias xp: byte_string(0 to packet'length-1) is packet;
  begin
    return xp(ip_off_dst0 to ip_off_dst3);
  end function;

  function ipv4_proto_get(packet: byte_string) return ip_proto_t
  is
    alias xp: byte_string(0 to packet'length-1) is packet;
  begin
    return to_integer(unsigned(xp(ip_off_proto)));
  end function;

  function ipv4_ihl_bytes_get(packet: byte_string) return integer
  is
    alias xp: byte_string(0 to packet'length-1) is packet;
  begin
    return to_integer(unsigned(xp(ip_off_type_len)(3 downto 0))) * 4;
  end function;

  function ipv4_data_get(packet: byte_string) return byte_stream
  is
    alias xp: byte_string(0 to packet'length-1) is packet;
    variable len: integer := ipv4_len_get(packet);
    variable off: integer := ipv4_ihl_bytes_get(packet);
    variable ret: byte_stream;
  begin
    if len > xp'length then
      report "Fragmented IPv4 Packet " & to_string(packet) & ", returning PDU start"
        severity warning;
      len := xp'length;
    end if;
    ret := new byte_string(0 to len-off-1);
    ret.all := xp(off to len - 1);
    return ret;
  end function;

  function ipv4_data_get(packet: byte_string) return byte_string
  is
    alias xp: byte_string(0 to packet'length-1) is packet;
    variable len: integer := ipv4_len_get(packet);
    variable off: integer := ipv4_ihl_bytes_get(packet);
  begin
    if len > xp'length then
      report "Fragmented IPv4 Packet " & to_string(packet) & ", returning PDU start"
        severity warning;
      len := xp'length;
    end if;
    return xp(off to len - 1);
  end function;

end package body;
