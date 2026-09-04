library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_math, work;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_math.int_ext.all;
use work.mac.all;
use work.ipv4.all;

-- Turnkey IPv4 host over the AXI4-Stream protocol suite: the mac,
-- ethernet, IPv4 and UDP layers, the ICMP echo responder, and ARP
-- resolution behind a per-port stack entry, bundled behind one
-- component.
--
-- The layer-1 side carries wire-level frames: the header_length_c
-- blocks, then the ethernet frame with its FCS.
--
-- Application contract, one stream pair per udp_port_c entry:
--
-- * transmit: [IPv4 context block][UDP context block][payload].
--   The IPv4 context length field must be eight plus the payload
--   length.  The host resolves the peer address transparently; an
--   unresolvable peer drops the datagram.
--
-- * receive: [header_length_c blocks][layer-2 context block][IPv4
--   context block][UDP context block][payload].  Echoing the two
--   context blocks back turns a received datagram into its reply.
--
-- The host answers ICMP echo requests and ARP requests on its own.
--
-- With dhcp_c set, the host runs a DHCP client on an internal UDP
-- port 68 pipe and takes its address from the lease instead of
-- local_address_i, which is then ignored: the stack runs as 0.0.0.0
-- until an address is acquired, and falls back there when the lease
-- is lost.  The lease information is reported on the dhcp_*_o ports,
-- all zero while dhcp_valid_o is deasserted, and permanently so when
-- dhcp_c is unset.  clock_i_hz_c paces the DHCP protocol timers and
-- hostname_c, when not empty, is sent to the server as the host
-- name.
--
-- Peers outside the local subnet resolve through the gateway: from
-- the lease netmask and router with dhcp_c, from local_netmask_i
-- and local_gateway_i otherwise.  An all-zero netmask treats every
-- peer as on-link.
package stream_host is

  component stream_ipv4_host is
    generic(
      config_c : config_t;
      header_length_c : integer_vector := null_integer_vector;
      udp_port_c : integer_vector;
      ttl_c : integer range 0 to 255 := 64;
      cache_count_l2_c : natural := 3;
      timeout_c : natural := 125000000;
      retry_count_c : natural := 3;
      dhcp_c : boolean := false;
      clock_i_hz_c : natural := 125000000;
      hostname_c : string := ""
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      local_hwaddr_i : in mac48_t;
      local_address_i : in ipv4_t := to_ipv4(0, 0, 0, 0);
      local_netmask_i : in ipv4_t := to_ipv4(0, 0, 0, 0);
      local_gateway_i : in ipv4_t := to_ipv4(0, 0, 0, 0);

      dhcp_address_o : out ipv4_t;
      dhcp_netmask_o : out ipv4_t;
      dhcp_router_o : out ipv4_t;
      dhcp_dns_o : out ipv4_t;
      dhcp_ntp_server_o : out ipv4_t;
      dhcp_valid_o : out std_ulogic;

      l1_header_i : in byte_string;

      l1_rx_i : in master_t;
      l1_rx_o : out slave_t;
      l1_tx_o : out master_t;
      l1_tx_i : in slave_t;

      to_app_o : out master_vector(0 to udp_port_c'length-1);
      to_app_i : in slave_vector(0 to udp_port_c'length-1);
      from_app_i : in master_vector(0 to udp_port_c'length-1);
      from_app_o : out slave_vector(0 to udp_port_c'length-1)
      );
  end component;

end package;
