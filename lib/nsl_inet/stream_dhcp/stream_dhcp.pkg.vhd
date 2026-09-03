library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_math, work;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_math.int_ext.all;
use work.mac.all;
use work.ipv4.all;

-- DHCPv4 client over the AXI4-Stream protocol suite, RFC 2131 and
-- RFC 2132.  The client is an application-contract endpoint on UDP
-- port 68: it speaks the same stream layout as any host application
-- pipe and expects to sit behind a resolver entry on transmit.  It
-- is byte-wide only; wider stacks place it behind a
-- stream_block_resizer pair.
--
-- Acquisition runs DISCOVER, OFFER, REQUEST, ACK, then rebinds the
-- lease at its renewal points: unicast REQUEST to the leasing server
-- at T1, broadcast REQUEST at T2, back to discovery on expiry or
-- NAK.  The first valid OFFER wins.  While the client holds no
-- address it sets the BROADCAST flag, so replies arrive as limited
-- broadcast, which the IPv4 layer accepts whatever local address is
-- configured.  A broadcast reply also passes the UDP checksum
-- validator, which folds the local address as pseudo-header
-- destination: the client only receives broadcast while the local
-- address is 0.0.0.0, and 0.0.0.0 and 255.255.255.255 fold
-- identically in one's complement.  Renewal replies are unicast.
--
-- RELEASE, DECLINE and the pre-use ARP probe of RFC 2131 are not
-- implemented.
package stream_dhcp is

  constant dhcp_server_port_c : natural := 67;
  constant dhcp_client_port_c : natural := 68;

  -- Fixed BOOTP fields, up to and excluding the magic cookie.
  constant dhcp_header_length_c : natural := 236;
  -- Messages shorter than this are padded, for BOOTP relay
  -- compatibility.  Counted over the UDP payload.
  constant dhcp_min_payload_length_c : natural := 300;

  constant dhcp_magic_cookie_c : byte_string(0 to 3)
    := (to_byte(16#63#), to_byte(16#82#), to_byte(16#53#), to_byte(16#63#));

  constant dhcp_op_bootrequest_c : byte := to_byte(1);
  constant dhcp_op_bootreply_c : byte := to_byte(2);

  subtype dhcp_option_t is byte;

  constant dhcp_option_pad_c : dhcp_option_t := to_byte(0);
  constant dhcp_option_netmask_c : dhcp_option_t := to_byte(1);
  constant dhcp_option_router_c : dhcp_option_t := to_byte(3);
  constant dhcp_option_dns_c : dhcp_option_t := to_byte(6);
  constant dhcp_option_hostname_c : dhcp_option_t := to_byte(12);
  constant dhcp_option_requested_address_c : dhcp_option_t := to_byte(50);
  constant dhcp_option_lease_time_c : dhcp_option_t := to_byte(51);
  constant dhcp_option_message_type_c : dhcp_option_t := to_byte(53);
  constant dhcp_option_server_id_c : dhcp_option_t := to_byte(54);
  constant dhcp_option_parameter_request_c : dhcp_option_t := to_byte(55);
  constant dhcp_option_renewal_time_c : dhcp_option_t := to_byte(58);
  constant dhcp_option_rebinding_time_c : dhcp_option_t := to_byte(59);
  constant dhcp_option_client_id_c : dhcp_option_t := to_byte(61);
  constant dhcp_option_end_c : dhcp_option_t := to_byte(255);

  constant dhcp_msg_discover_c : byte := to_byte(1);
  constant dhcp_msg_offer_c : byte := to_byte(2);
  constant dhcp_msg_request_c : byte := to_byte(3);
  constant dhcp_msg_decline_c : byte := to_byte(4);
  constant dhcp_msg_ack_c : byte := to_byte(5);
  constant dhcp_msg_nak_c : byte := to_byte(6);
  constant dhcp_msg_release_c : byte := to_byte(7);

  -- Client engine.  config_c must be one byte wide.
  --
  -- Packets on rx_i carry the header_length_c blocks, then the DHCP
  -- message as payload; the blocks are skipped without
  -- interpretation, so the generic must list every block ahead of
  -- the payload, layer-2, IPv4 and UDP contexts included.  Packets
  -- ending rejected are discarded.
  --
  -- Packets on tx_o follow the application transmit contract:
  -- [IPv4 context][UDP context][payload], peer port
  -- dhcp_server_port_c, casting broadcast except for the renewal
  -- unicast to the leasing server.
  --
  -- clock_i_hz_c paces the one-second protocol ticker.  When
  -- hostname_c is not empty it is sent as the host name option.
  --
  -- address_o, netmask_o, router_o and dns_o hold the lease
  -- information while valid_o is asserted and read 0.0.0.0
  -- otherwise; an absent option reads 0.0.0.0.  Deasserting
  -- enable_i drops the lease silently and idles the engine.
  component stream_dhcp_client is
    generic(
      config_c : config_t;
      header_length_c : integer_vector := null_integer_vector;
      clock_i_hz_c : natural;
      hostname_c : string := ""
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      enable_i : in std_ulogic := '1';
      hwaddr_i : in mac48_t;

      rx_i : in master_t;
      rx_o : out slave_t;
      tx_o : out master_t;
      tx_i : in slave_t;

      address_o : out ipv4_t;
      netmask_o : out ipv4_t;
      router_o : out ipv4_t;
      dns_o : out ipv4_t;
      valid_o : out std_ulogic
      );
  end component;

end package;
