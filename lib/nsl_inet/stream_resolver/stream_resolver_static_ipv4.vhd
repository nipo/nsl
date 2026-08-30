library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_math, work;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_math.int_ext.all;
use work.ipv4.all;
use work.mac.all;
use work.stream.all;
use work.stream_ethernet.all;
use work.stream_ipv4.all;

-- Static IPv4 resolver.
--
-- The query block is the serialized IPv4 context of nsl_inet.
-- stream_ipv4, transported padded to a whole count of beats.  The
-- response is the l1_header_i bytes, the layer-2 context block, then
-- the query block echoed verbatim, padding included.
--
-- A query whose casting is broadcast resolves to the ethernet
-- broadcast address without any lookup.  Any other query resolves
-- through the address_c table; a miss answers with a zeroed layer-2
-- context block and the reject flag set on the last beat.
entity stream_resolver_static_ipv4 is
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
end entity;

architecture beh of stream_resolver_static_ipv4 is

  constant l1_bytes_c : natural := context_byte_count(config_c, header_length_c);
  constant l2_bytes_c : natural
    := context_byte_count(config_c, (0 => l2_context_length_c));
  constant query_bytes_c : natural
    := context_byte_count(config_c, (0 => ip_context_length_c));
  constant response_bytes_c : natural := l1_bytes_c + l2_bytes_c + query_bytes_c;
  constant response_beats_c : natural := response_bytes_c / config_c.data_width;

  constant entry_count_c : natural := address_c'length;
  constant address_l_c : ipv4_vector(0 to entry_count_c-1) := address_c;
  constant hwaddr_l_c : mac48_vector(0 to entry_count_c-1) := hwaddr_c;

  type match_t is
  record
    hit: boolean;
    hwaddr: mac48_t;
  end record;

  -- Hardware address of peer in the table.  The compare cone and the
  -- table read are one and the same, and their result is registered
  -- by the state that runs them.
  function lookup(peer: ipv4_t) return match_t
  is
    variable ret: match_t := (hit => false, hwaddr => (others => x"00"));
  begin
    -- Scanned backwards, so that the first matching entry of the
    -- table is the one left selected.
    for i in entry_count_c-1 downto 0
    loop
      if address_l_c(i) = peer then
        ret := (hit => true, hwaddr => hwaddr_l_c(i));
      end if;
    end loop;
    return ret;
  end function;

  type state_t is (
    ST_RESTART,
    -- Collecting the query block
    ST_QUERY,
    -- Resolving the query block to a layer-2 context
    ST_LOOKUP,
    -- Assembling the response around the resolved context
    ST_BUILD,
    -- Emitting the response
    ST_RESPONSE
    );

  type regs_t is
  record
    state: state_t;
    query: byte_string(0 to query_bytes_c-1);
    fillness: natural range 0 to query_bytes_c;
    -- Layer-2 context block the query resolved to
    l2: byte_string(0 to l2_context_length_c-1);
    response: byte_string(0 to response_bytes_c-1);
    to_go: natural range 0 to response_beats_c;
    rejected: boolean;
  end record;

  signal r, rin: regs_t;

begin

  assert address_c'length = hwaddr_c'length
    report "Address and hardware address tables must have the same length"
    severity failure;

  assert l1_bytes_c = 0 or l1_header_i'length = l1_bytes_c
    report "l1_header_i must carry the transported size of header_length_c"
    severity failure;

  -- A query packet is exactly the query block: the beat completing the
  -- block is the packet's last beat, and no beat before it is.
  monitor: process(clock_i) is
  begin
    if rising_edge(clock_i) and reset_n_i = '1' then
      if r.state = ST_QUERY and is_valid(config_c, query_i) then
        assert (r.fillness + config_c.data_width = query_bytes_c)
          = is_last(config_c, query_i)
          report "Query packet size does not match the query block size"
          severity failure;
      end if;
    end if;
  end process;

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_RESTART;
    end if;
  end process;

  transition: process(r, query_i, response_i, l1_header_i) is
    variable ip_v: ip_context_t;
    variable match_v: match_t;
  begin
    rin <= r;

    case r.state is
      when ST_RESTART =>
        rin.state <= ST_QUERY;
        rin.fillness <= 0;
        rin.rejected <= false;
        rin.to_go <= 0;

      when ST_QUERY =>
        if is_valid(config_c, query_i) then
          rin.query <= r.query(config_c.data_width to query_bytes_c-1)
                       & bytes(config_c, query_i);

          if r.fillness + config_c.data_width = query_bytes_c then
            rin.fillness <= 0;
            rin.state <= ST_LOOKUP;
          elsif is_last(config_c, query_i) then
            -- Packet ends inside the query block, nothing to resolve
            rin.fillness <= 0;
          else
            rin.fillness <= r.fillness + config_c.data_width;
          end if;
        end if;

      when ST_LOOKUP =>
        ip_v := from_bytes(r.query(0 to ip_context_length_c-1));
        match_v := lookup(ip_v.peer);

        case ip_v.casting is
          when IP_CAST_BROADCAST =>
            rin.l2 <= to_bytes(l2_context_t'(peer => ethernet_broadcast_addr_c,
                                             casting => L2_CAST_BROADCAST));
            rin.rejected <= false;

          when IP_CAST_UNICAST =>
            if match_v.hit then
              rin.l2 <= to_bytes(l2_context_t'(peer => match_v.hwaddr,
                                               casting => L2_CAST_UNICAST));
              rin.rejected <= false;
            else
              -- A miss answers with a zeroed context block, which is
              -- what a null unicast peer serializes to
              rin.l2 <= to_bytes(l2_context_t'(peer => (others => x"00"),
                                               casting => L2_CAST_UNICAST));
              rin.rejected <= true;
            end if;
        end case;

        rin.state <= ST_BUILD;

      when ST_BUILD =>
        rin.response <= context_head(l1_header_i, l1_bytes_c)
                        & context_pad(config_c, r.l2)
                        & r.query;
        rin.to_go <= response_beats_c;
        rin.state <= ST_RESPONSE;

      when ST_RESPONSE =>
        if is_ready(config_c, response_i) then
          rin.to_go <= r.to_go - 1;
          rin.response(0 to response_bytes_c-1-config_c.data_width)
            <= r.response(config_c.data_width to response_bytes_c-1);
          if r.to_go = 1 then
            rin.state <= ST_RESTART;
          end if;
        end if;
    end case;
  end process;

  moore: process(r) is
  begin
    query_o <= accept(config_c, r.state = ST_QUERY);

    if r.state = ST_RESPONSE then
      response_o <= reject_set(config_c,
                               transfer(config_c,
                                        bytes => r.response(0 to config_c.data_width-1),
                                        valid => true,
                                        last => r.to_go = 1),
                               r.rejected and r.to_go = 1);
    else
      response_o <= transfer_defaults(config_c);
    end if;
  end process;

end architecture;
