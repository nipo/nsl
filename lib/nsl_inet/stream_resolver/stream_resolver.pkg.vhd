library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_math, work;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_math.int_ext.all;
use work.mac.all;
use work.ipv4.all;

-- Address resolution service for the AXI4-Stream protocol suite.
--
-- Applications wanting to transmit do not know the protocol
-- stacking: they hand the stack entry point a packet made of the
-- peer information, the context of the layer they talk to, and
-- their PDU.  The entry point queries a resolver with the peer
-- information alone, and prepends the resolver's answer -- every
-- block the layers below expect -- to the rest of the packet.  The
-- protocol layers stay pure formatters, agnostic to resolution;
-- responders never resolve at all, they echo the symmetrical
-- context of the packets they answer.
--
-- Resolver contract
-- =================
--
-- A query packet is a single block carrying the peer information.
-- Its contents are a contract between the application and the
-- resolver instantiated in the stack; for the IPv4 resolvers of
-- this package and of stream_arp, it is the serialized IPv4 context
-- (nsl_inet.stream_ipv4), so an application provides exactly the
-- context it owes the IPv4 layer anyway.
--
-- A response packet is the blocks below the resolver's sibling
-- layer -- for IPv4 resolvers, the header_length_c blocks and the
-- layer-2 context block -- followed by the query block echoed
-- verbatim.  A resolver always answers every query, in order; a
-- resolution failure is a response with the reject flag set on its
-- last beat.  A query whose casting is broadcast resolves to the
-- broadcast link address without any lookup.
package stream_resolver is

  -- Splices resolution into an egress stream.  Input packets are
  -- [peer information block][remainder]; the peer information block
  -- is diverted to the resolver while the remainder is held in an
  -- internal buffer, and the resolver's response blocks are emitted
  -- in front of the remainder.  A rejected response drops the held
  -- packet entirely.
  --
  -- The component is agnostic to the contents and sizes of both the
  -- response and the remainder.  One resolution is in flight at a
  -- time; the input is backpressured meanwhile.  Packets whose
  -- remainder overflows the buffer are dropped.
  component stream_resolver_entry is
    generic(
      config_c : config_t;
      query_length_c : natural;
      buffer_depth_l2_c : natural := 11
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      in_i : in master_t;
      in_o : out slave_t;

      query_o : out master_t;
      query_i : in slave_t;
      response_i : in master_t;
      response_o : out slave_t;

      out_o : out master_t;
      out_i : in slave_t
      );
  end component;

  -- Shares one resolver between several query sources.  Queries are
  -- funneled in arrival order and the matching responses dispatched
  -- back to their source.
  component stream_resolver_arbiter is
    generic(
      config_c : config_t;
      source_count_c : positive;
      pending_count_l2_c : natural := 2
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      query_i : in master_vector(0 to source_count_c-1);
      query_o : out slave_vector(0 to source_count_c-1);
      response_o : out master_vector(0 to source_count_c-1);
      response_i : in slave_vector(0 to source_count_c-1);

      resolver_query_o : out master_t;
      resolver_query_i : in slave_t;
      resolver_response_i : in master_t;
      resolver_response_o : out slave_t
      );
  end component;

  -- Static IPv4 resolver: the oracle of a fully static
  -- configuration.  The peer address is looked up in the address_c
  -- table and resolves to the hwaddr_c entry of the same index; a
  -- miss is a resolution failure.  header_length_c and l1_header_i
  -- carry the blocks below the ethernet layer, echoed at the head
  -- of every response.
  component stream_resolver_static_ipv4 is
    generic(
      config_c : config_t;
      header_length_c : integer_vector := null_integer_vector;
      address_c : ipv4_vector;
      hwaddr_c : mac48_vector
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      l1_header_i : in byte_string;

      query_i : in master_t;
      query_o : out slave_t;

      response_o : out master_t;
      response_i : in slave_t
      );
  end component;

end package;
