library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_data, nsl_inet;
use nsl_bnoc.committed.all;
use nsl_bnoc.framed.all;
use nsl_inet.ethernet.all;
use nsl_inet.ipv4.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.text.all;

package arp is

  -- ARP layer is responsible for crafting a suitable layer 1/2 header
  component arp_ethernet is
    generic(
      -- L2 header length is fixed by MAC layer
      header_length_c : integer := 0;
      cache_count_c : integer := 1;
      clock_i_hz_c : natural
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      -- Layer-1 header, supposed to be fixed, if any.
      header_i : in byte_string(0 to header_length_c-1) := (others => x"00");

      -- Unicast addresses
      unicast_i : in ipv4_t;
      -- If target address does not match unicast masked to mask,
      -- actually lookup ip mapping of gateway.
      netmask_i : in ipv4_t := (others => x"ff");
      -- If all zero, dont divert to default route
      gateway_i : in ipv4_t := (others => x"00");
      hwaddr_i : in nsl_inet.ethernet.mac48_t;

      -- Layer 2 link
      to_l2_o : out committed_req;
      to_l2_i : in committed_ack;
      from_l2_i : in committed_req;
      from_l2_o : out committed_ack;

      -- Rx notification API
      -- l1 header | mac | context | ipv4 | context
      notify_i : in byte_string(0 to header_length_c+7+4) := (others => x"00");
      notify_valid_i : in std_ulogic := '0';

      -- Resolver API for IP usage
      request_i : in framed_req;
      request_o : out framed_ack;
      response_o : out framed_req;
      response_i : in framed_ack
      );
  end component;

  -- Sends request to the resolver
  -- If resolver fails, drops the packet
  component arp_resolver is
    generic(
      -- Pre-header length
      header_length_c : natural := 0;
      ha_length_c : natural;
      pa_length_c : positive
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      -- Upper layer I/O, should contain:
      -- * header [header_length_c]
      -- * Protocol address [pa_length_c]
      -- * PDU [*]
      -- * Validity
      tx_in_i : in committed_req;
      tx_in_o : out committed_ack;
      rx_out_o : out committed_req;
      rx_out_i : in committed_ack;

      -- Lower layer I/O
      -- * header [header_length_c]
      -- * Hardware address [ha_length_c]
      -- * Protocol address [pa_length_c]
      -- * PDU
      -- * Validity
      rx_in_i : in committed_req;
      rx_in_o : out committed_ack;
      tx_out_o : out committed_req;
      tx_out_i : in committed_ack;
      
      -- Resolver API
      -- Sends:
      -- * Protocol address [pa_length_c]
      request_o : out framed_req;
      request_i : in framed_ack;
      -- Receives:
      -- * TTL -- ticks [1], if last = 1, consider lookup failed
      -- * Hardware address [ha_length_c]
      response_i : in framed_req;
      response_o : out framed_ack
      );
  end component;

end package;
