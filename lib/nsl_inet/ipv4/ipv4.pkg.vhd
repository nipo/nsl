library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_data, nsl_inet;
use nsl_bnoc.committed.all;
use nsl_bnoc.framed.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.text.all;

-- IPv4 is a layer-3 protocol, it requires ICMP to function
-- correctly, ICMP is layer-4. Both are defined here.
package ipv4 is

  -- IPv4 address, in network order
  subtype ipv4_t is byte_string(0 to 3);

  subtype ipv4_nibble_t is integer range 0 to 255;
  function to_ipv4(a, b, c, d: ipv4_nibble_t) return ipv4_t;
  function ip_to_string(ip: ipv4_t) return string;

  subtype ip_proto_t is integer range 0 to 255;
  type ip_proto_vector is array(natural range <>) of ip_proto_t;
  constant ip_proto_vector_null_c: ip_proto_vector(0 to -1) := (others => 0);

  subtype ip_packet_id_t is unsigned(15 downto 0);

  constant ip_proto_icmp : ip_proto_t := 1;
  constant ip_proto_tcp  : ip_proto_t := 6;
  constant ip_proto_udp  : ip_proto_t := 17;
  constant ip_proto_gre  : ip_proto_t := 47;

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
      ip_proto_c : ip_proto_vector
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

  subtype checksum_t is unsigned(16 downto 0);
  
  function checksum_update(state: checksum_t; d: byte)
    return checksum_t;

  function checksum_update(state: checksum_t; s: byte_string)
    return checksum_t;
  function checksum_is_valid(data : byte_string) return boolean;

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

  function checksum_update(state: checksum_t; d: byte)
    return checksum_t
  is
    variable a, b, ret: checksum_t;
  begin
    a := x"00" & state(16) & unsigned(d);
    b := "0" & state(7 downto 0) & state(15 downto 8);
    ret := a + b;
    return ret;
  end function;

  function checksum_update2(state: checksum_t; s: byte_string(0 to 1))
    return checksum_t
  is
    variable a, b, ret: checksum_t;
    variable c: unsigned(0 downto 0);
  begin
    a := "0" & from_be(s);
    b := "0" & state(15 downto 0);
    c := state(16 downto 16);
    ret := a + b + c;
    return ret;
  end function;    

  function checksum_update(state: checksum_t; s: byte_string)
    return checksum_t
  is
    variable ret: checksum_t := state;
  begin
    if s'length = 2 then
      return checksum_update2(ret, s);
    end if;
    
    for i in s'range
    loop
      ret := checksum_update(ret, s(i));
    end loop;
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
    variable chk : checksum_t := (others => '0');
  begin
    header(ip_off_type_len) := x"45";
    header(ip_off_len_h to ip_off_len_l) := to_be(to_unsigned(header'length + data'length, 16));
    header(ip_off_id_h to ip_off_id_l) := to_be(id);
    header(ip_off_ttl) := to_byte(ttl);
    header(ip_off_proto) := to_byte(proto);
    header(ip_off_src0 to ip_off_src3) := source;
    header(ip_off_dst0 to ip_off_dst3) := destination;

    chk := checksum_update(chk, header);
    chk := checksum_update(chk, x"00");
    chk := checksum_update(chk, x"00");
    header(ip_off_chk_h to ip_off_chk_l) := to_be(unsigned(not chk(15 downto 0)));

    return header & data;
  end function;

  function ipv4_is_header_valid(
    datagram : byte_string) return boolean
  is
    alias xd: byte_string(0 to datagram'length-1) is datagram;
    variable header_size : integer;
    variable chk : checksum_t := (others => '0');
  begin
    header_size := to_integer(unsigned(xd(ip_off_type_len)(4 downto 0)));
    if header_size < 5 then
      return false;
    end if;

    header_size := header_size * 4;
    if xd'length < header_size then
      return false;
    end if;

    chk := checksum_update(chk, xd(0 to header_size - 1));
    chk := checksum_update(chk, x"00");
    
    if chk /= "01111111111111111" then
      return false;
    end if;

    return true;
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
    variable chk: checksum_t := (others => '0');
  begin
    hdr(0) := to_byte(typ);
    hdr(1) := to_byte(code);
    hdr(4 to 7) := header;

    chk := checksum_update(chk, hdr);
    chk := checksum_update(chk, data);

    -- This one is for carry propagation
    chk := checksum_update(chk, x"00");
    if (data'length mod 2) = 0 then
      -- This one for re-alignment
      chk := checksum_update(chk, x"00");
    end if;

    hdr(2 to 3) := to_be(not chk(15 downto 0));

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

  function checksum_is_valid(
    data : byte_string)
    return boolean
  is
    variable chk: checksum_t := (others => '0');
  begin
    chk := checksum_update(chk, data);
    chk := checksum_update(chk, x"00");
    chk := checksum_update(chk, x"00");

    return chk(15 downto 0) = x"ffff";
  end function;

end package body;
