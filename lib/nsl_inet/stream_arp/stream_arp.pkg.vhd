library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_math, work;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_math.int_ext.all;
use work.mac.all;
use work.ipv4.all;

-- ARP over ethernet for IPv4, as an implementation of the address
-- resolution contract of nsl_inet.stream_resolver.
--
-- The resolver sits beside its sibling IPv4 layer: queries carry the
-- serialized IPv4 context, whose peer address drives the lookup and
-- whose remaining bytes are echoed untouched.  Responses follow the
-- resolver contract: the header_length_c blocks (fed through
-- l1_header_i), the layer-2 context block, then the query block.
--
-- On the ethernet side, the component owns the 0x0806 ethertype pipe
-- pair of the ethernet layer: it answers ARP requests for
-- local_address_i, learns from requests and replies addressed to the
-- local station, and emits broadcast requests of its own to resolve
-- cache misses.  A miss is retried up to retry_count_c times,
-- timeout_c clock cycles apart; exhaustion answers the query with
-- the reject flag set, so a resolver client never hangs.
--
-- When netmask_i is non-zero, a queried peer outside the local
-- subnet is diverted to the gateway: gateway_i drives the lookup,
-- the cache and the requests on the wire, while the query block is
-- still echoed untouched.  The all-zero netmask (the default)
-- treats every peer as on-link; an off-subnet peer with no gateway
-- configured resolves 0.0.0.0 and fails like any unanswered lookup.
package stream_arp is

  component stream_arp_resolver is
    generic(
      config_c : config_t;
      header_length_c : integer_vector := null_integer_vector;
      cache_count_l2_c : natural := 3;
      timeout_c : natural := 125000000;
      retry_count_c : natural := 3
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      local_hwaddr_i : in mac48_t;
      local_address_i : in ipv4_t;
      netmask_i : in ipv4_t := to_ipv4(0, 0, 0, 0);
      gateway_i : in ipv4_t := to_ipv4(0, 0, 0, 0);

      l1_header_i : in byte_string;

      -- Ethernet layer 0x0806 pipe
      from_l2_i : in master_t;
      from_l2_o : out slave_t;
      to_l2_o : out master_t;
      to_l2_i : in slave_t;

      query_i : in master_t;
      query_o : out slave_t;

      response_o : out master_t;
      response_i : in slave_t
      );
  end component;

end package;
