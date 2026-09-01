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
package stream_host is

  component stream_ipv4_host is
    generic(
      config_c : config_t;
      header_length_c : integer_vector := null_integer_vector;
      udp_port_c : integer_vector;
      ttl_c : integer range 0 to 255 := 64;
      cache_count_l2_c : natural := 3;
      timeout_c : natural := 125000000;
      retry_count_c : natural := 3
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      local_hwaddr_i : in mac48_t;
      local_address_i : in ipv4_t;

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
