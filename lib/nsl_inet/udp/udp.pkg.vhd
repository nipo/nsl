library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_data, work;
use nsl_bnoc.committed.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.text.all;
use work.ipv4.all;
use work.checksum.all;

-- UDP is a layer-4 protocol. It is meant to be transported on IP.
package udp is

  subtype udp_port_t is integer range 0 to 65535;
  type udp_port_vector is array(integer range <>) of udp_port_t;
  constant udp_port_vector_null_c: udp_port_vector(0 to -1) := (others => 0);
  constant udp_layer_header_length_c: integer := 2;
  
  -- Frame structure from/to layer 3
  -- * Some fixed context, passed through [0..N] *
  -- * Layer 4 PDU size, big endian [2]
  -- * Layer 4 data [*]
  -- * Status
  --   [0]   Validity bit
  --   [7:1] Reserved
  
  -- Frame structure from/to layer 5, after UDP receiver
  -- * Upper layer context, passed through [0..N] *
  -- * Remote port, MSB first [2]
  -- * Local port, MSB first [2]
  -- * Layer 5 data [N]
  -- * Status
  --   [0]   Validity bit
  --   [7:1] Reserved
  
  -- Frame structure from/to layer 5, after UDP layer
  -- * Upper layer context, passed through [0..N] *
  -- * Remote port, MSB first [2]
  -- * Layer 5 data [N]
  -- * Status
  --   [0]   Validity bit
  --   [7:1] Reserved

  -- [*] For instance, stacked on IPv4 implementation, passed through
  -- context will be:
  -- * L1 header
  -- * L2 header
  -- * Peer IP address
  -- * IP Context (address type)
  -- * IP proto
  
  component udp_receiver is
    generic(
      -- Upper-layer-specific data size
      header_length_c : integer
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      -- Frame from layer 3
      l3_i : in committed_req;
      l3_o : out committed_ack;

      -- To layer 5
      l5_o : out committed_req;
      l5_i : in committed_ack
      );
  end component;

  component udp_transmitter is
    generic(
      mtu_c : integer := 1500;
      -- Flit count to pass through at the start of a packet
      header_length_c : integer
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      -- From layer 5
      l5_i : in committed_req;
      l5_o : out committed_ack;

      -- To layer 3
      l3_o : out committed_req;
      l3_i : in committed_ack
      );
  end component;

  component udp_layer is
    generic(
      tx_mtu_c : integer := 1500;
      udp_port_c : udp_port_vector;
      header_length_c : integer
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      -- Frame structure from/to layer 5
      -- * Upper layer context, passed through [header_length_c]
      -- * Remote port, MSB first [2]
      -- * Layer 5 data [N]
      -- * Status
      --   [0]   Validity bit
      --   [7:1] Reserved
      to_l5_o : out committed_req_array(0 to udp_port_c'length - 1);
      to_l5_i : in committed_ack_array(0 to udp_port_c'length - 1);
      from_l5_i : in committed_req_array(0 to udp_port_c'length - 1);
      from_l5_o : out committed_ack_array(0 to udp_port_c'length - 1);

      from_l3_i : in committed_req;
      from_l3_o : out committed_ack;
      to_l3_o : out committed_req;
      to_l3_i : in committed_ack
      );
  --@-- grouped name:l3, members:to_l3;from_l3
  --@-- grouped name:l5, members:to_l5;from_l5
  end component;

  function udp_pack(
    destination, source : udp_port_t;
    data : byte_string;
    destination_ip, source_ip: ipv4_t := to_ipv4(0,0,0,0)) return byte_string;

  function udp_dest_get(datagram: byte_string) return udp_port_t;
  function udp_source_get(datagram: byte_string) return udp_port_t;
  function udp_len_get(datagram: byte_string) return integer;
  function udp_data_get(datagram: byte_string) return byte_stream;
  
end package;

package body udp is
  
  function udp_pack(
    destination, source : udp_port_t;
    data : byte_string;
    destination_ip, source_ip: ipv4_t := to_ipv4(0,0,0,0)) return byte_string
  is
    variable dp, sp, len, c: unsigned(15 downto 0);
    variable check : checksum_acc_t := (others => '0');
  begin
    dp := to_unsigned(destination, 16);
    sp := to_unsigned(source, 16);
    len := to_unsigned(data'length + 8, 16);

    check := checksum_update(check, source_ip);
    check := checksum_update(check, destination_ip);
    check := checksum_update(check, x"00");
    check := checksum_update(check, to_byte(ip_proto_udp));
    check := checksum_update(check, to_be(len));
    check := checksum_update(check, to_be(sp) & to_be(dp) & to_be(len) & x"00" & x"00" & data);

    return to_be(sp) & to_be(dp) & to_be(len) & checksum_spill(check, (data'length mod 2) = 1) & data;
  end function;

  function udp_source_get(datagram: byte_string) return udp_port_t
  is
    alias xd: byte_string(0 to datagram'length-1) is datagram;
  begin
    return to_integer(from_be(xd(0 to 1)));
  end function;

  function udp_dest_get(datagram: byte_string) return udp_port_t
  is
    alias xd: byte_string(0 to datagram'length-1) is datagram;
  begin
    return to_integer(from_be(xd(2 to 3)));
  end function;

  function udp_len_get(datagram: byte_string) return integer
  is
    alias xd: byte_string(0 to datagram'length-1) is datagram;
  begin
    return to_integer(from_be(xd(4 to 5)));
  end function;

  function udp_data_get(datagram: byte_string) return byte_stream
  is
    alias xd: byte_string(0 to datagram'length-1) is datagram;
    variable len: integer := udp_len_get(datagram);
    variable ret: byte_stream;
  begin
    if len > xd'length then
      report "Invalid short UDP datagram " & to_string(datagram) & ", returning PDU start"
        severity warning;
      len := xd'length;
    end if;
    ret := new byte_string(0 to len-8-1);
    ret.all := xd(8 to len - 1);
    return ret;
  end function;
  

end package body;
