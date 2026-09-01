library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_logic, nsl_math, work;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_logic.bool.all;
use nsl_math.int_ext.all;
use work.ipv4.all;
use work.stream.all;
use work.stream_ipv4.all;
use work.stream_udp.all;

entity stream_udp_receiver is
  generic(
    config_c : config_t;
    header_length_c : integer_vector := null_integer_vector;
    udp_port_c : integer_vector
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    local_address_i : in ipv4_t;

    in_i : in master_t;
    in_o : out slave_t;

    out_o : out master_vector(0 to udp_port_c'length-1);
    out_i : in slave_vector(0 to udp_port_c'length-1)
    );
end entity;

architecture beh of stream_udp_receiver is

  constant out_count_c : natural := udp_port_c'length;
  constant lengths_c : integer_vector(0 to header_length_c'length-1)
    := header_length_c;
  constant port_l_c : integer_vector(0 to out_count_c-1) := udp_port_c;
  -- Transported size of the blocks forwarded verbatim, preceding the
  -- UDP header on the IPv4 side and the context block on the
  -- application side.
  constant pre_size_c : integer
    := context_byte_count(config_c, header_length_c);
  constant ip_context_block_c : integer
    := context_byte_count(config_c, (0 => ip_context_length_c));
  -- The IPv4 context is the last of the forwarded blocks, so it
  -- starts one block short of the end of the prefix.
  constant ip_context_offset_c : integer := pre_size_c - ip_context_block_c;
  constant context_block_c : integer
    := context_byte_count(config_c, (0 => udp_context_length_c));
  constant in_header_length_c : integer := pre_size_c + udp_header_length_c;
  constant out_header_length_c : integer := pre_size_c + context_block_c;

  -- Cycles between the routing request and the response: length and
  -- port comparisons on one, the output they select on the next.
  constant decide_latency_c : natural := 2;

  -- Elasticity absorbing the routing decision and the emission of
  -- the response header without stalling the input: response header
  -- beats plus arbitration and decision latency.
  constant fifo_depth_c : natural
    := out_header_length_c / config_c.data_width + decide_latency_c + 7;

  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_DECIDE,
    ST_RESPOND
    );

  -- One bit per output, set when the datagram carries the port bound
  -- to it.  Bindings are compared side by side.
  function port_match(destination_port: integer)
    return std_ulogic_vector
  is
    variable ret: std_ulogic_vector(0 to out_count_c-1);
  begin
    for i in ret'range
    loop
      ret(i) := to_logic(port_l_c(i) = destination_port);
    end loop;

    return ret;
  end function;

  -- Output a match vector selects.  A binding table naming the same
  -- port twice resolves to its last entry.
  function match_index(match: std_ulogic_vector)
    return natural
  is
    variable ret: natural range 0 to out_count_c-1 := 0;
  begin
    for i in match'range
    loop
      if match(i) = '1' then
        ret := i;
      end if;
    end loop;

    return ret;
  end function;

  function match_any(match: std_ulogic_vector)
    return boolean
  is
    variable ret: std_ulogic := '0';
  begin
    for i in match'range
    loop
      ret := ret or match(i);
    end loop;

    return ret = '1';
  end function;

  type regs_t is
  record
    state: state_t;
    -- Outcome of the comparisons the UDP header feeds, kept apart
    -- from the output they select: the two take a cycle each.
    accepted: boolean;
    match: std_ulogic_vector(0 to out_count_c-1);
    drop: boolean;
    destination: natural range 0 to out_count_c-1;
    header: byte_string(0 to out_header_length_c-1);
  end record;

  signal r, rin: regs_t;

  signal validated_s: bus_t;

  signal route_valid_s, route_ready_s, route_drop_s: std_ulogic;
  signal route_in_header_s: byte_string(0 to in_header_length_c-1);
  signal route_out_header_s: byte_string(0 to out_header_length_c-1);
  signal route_destination_s: natural range 0 to out_count_c-1;
  signal route_source_s: natural range 0 to 0;

begin

  assert lengths_c'length > 0
    and lengths_c(lengths_c'right) = ip_context_length_c
    report "Last forwarded block must be the IPv4 context"
    severity failure;

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_RESET;
    end if;
  end process;

  transition: process(r, route_valid_s, route_in_header_s) is
    variable header_v: byte_string(0 to udp_header_length_c-1);
    variable ip_context_v: ip_context_t;
    variable source_port_v, destination_port_v, length_v: integer
      range 0 to 65535;
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_IDLE;

      when ST_IDLE =>
        if route_valid_s = '1' then
          ip_context_v := from_bytes(route_in_header_s(ip_context_offset_c
                                                       to ip_context_offset_c
                                                       + ip_context_length_c-1));
          header_v := route_in_header_s(pre_size_c
                                        to pre_size_c
                                        + udp_header_length_c-1);
          source_port_v := to_integer(from_be(header_v(0 to 1)));
          destination_port_v := to_integer(from_be(header_v(2 to 3)));
          length_v := to_integer(from_be(header_v(4 to 5)));

          -- The IPv4 layer trims its payload to the length its header
          -- declares, so a datagram whose own length field disagrees
          -- is malformed.
          rin.state <= ST_DECIDE;
          rin.header <= route_in_header_s(0 to pre_size_c-1)
                        & context_pad(config_c,
                                      to_bytes(udp_context_t'(peer_port => source_port_v)));
          rin.accepted <= length_v = ip_context_v.length;
          rin.match <= port_match(destination_port_v);
        end if;

      when ST_DECIDE =>
        rin.state <= ST_RESPOND;
        rin.destination <= match_index(r.match);
        rin.drop <= not (r.accepted and match_any(r.match));

      when ST_RESPOND =>
        rin.state <= ST_IDLE;
    end case;
  end process;

  moore: process(r) is
  begin
    route_ready_s <= to_logic(r.state = ST_RESPOND);
    route_drop_s <= to_logic(r.drop);
    route_destination_s <= r.destination;
    route_out_header_s <= r.header;
  end process;

  -- Validation happens before routing so that the verdict rides on
  -- the last beat the router forwards.
  validator: work.stream_udp.stream_udp_validator
    generic map(
      config_c => config_c,
      header_length_c => header_length_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      local_address_i => local_address_i,

      in_i => in_i,
      in_o => in_o,

      out_o => validated_s.m,
      out_i => validated_s.s
      );

  router: nsl_amba.stream_routing.axi4_stream_router
    generic map(
      config_c => config_c,
      in_count_c => 1,
      out_count_c => out_count_c,
      in_header_length_c => in_header_length_c,
      out_header_length_c => out_header_length_c,
      fifo_depth_c => fifo_depth_c
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i => clock_i,

      in_i(0) => validated_s.m,
      in_o(0) => validated_s.s,

      out_o => out_o,
      out_i => out_i,

      route_valid_o => route_valid_s,
      route_header_o => route_in_header_s,
      route_source_o => route_source_s,

      route_ready_i => route_ready_s,
      route_header_i => route_out_header_s,
      route_destination_i => route_destination_s,
      route_drop_i => route_drop_s
      );

end architecture;
