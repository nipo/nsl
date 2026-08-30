library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_logic, nsl_math, work;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_logic.bool.all;
use nsl_math.int_ext.all;
use work.mac.all;
use work.stream.all;
use work.stream_mac.all;
use work.stream_ethernet.all;

entity stream_ethernet_receiver is
  generic(
    config_c : config_t;
    header_length_c : integer_vector := null_integer_vector;
    ethertype_c : ethertype_vector
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    local_address_i : in mac48_t;

    in_i : in master_t;
    in_o : out slave_t;

    out_o : out master_vector(0 to ethertype_c'length-1);
    out_i : in slave_vector(0 to ethertype_c'length-1)
    );
end entity;

architecture beh of stream_ethernet_receiver is

  constant out_count_c : natural := ethertype_c'length;
  -- Transported size of the blocks forwarded verbatim, preceding the
  -- ethernet frame block on the mac side and the context block on the
  -- layer-3 side.
  constant pre_size_c : natural
    := context_byte_count(config_c, header_length_c);
  constant frame_block_c : natural
    := ethernet_frame_offset(config_c) + ethernet_header_length_c;
  constant context_block_c : natural
    := context_byte_count(config_c, (0 => l2_context_length_c));
  constant in_header_length_c : natural := pre_size_c + frame_block_c;
  constant out_header_length_c : natural := pre_size_c + context_block_c;
  -- Offsets of the ethernet header fields inside the peeled header,
  -- past the forwarded blocks and the frame block front padding.
  constant da_offset_c : natural := pre_size_c + ethernet_frame_offset(config_c);
  constant sa_offset_c : natural := da_offset_c + 6;
  constant et_offset_c : natural := da_offset_c + 12;
  constant ethertype_l_c : ethertype_vector(0 to out_count_c-1) := ethertype_c;

  -- Cycles between the routing request and the response: address and
  -- ethertype comparisons on one, the output they select on the next.
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

  -- Casting the destination address stands for.
  function casting_of(da: mac48_t) return l2_casting_t
  is
  begin
    if is_broadcast(da) then
      return L2_CAST_BROADCAST;
    end if;

    return L2_CAST_UNICAST;
  end function;

  -- One bit per output, set when the frame carries the ethertype
  -- bound to it.  Bindings are compared side by side.
  function ethertype_match(ethertype: ethertype_t)
    return std_ulogic_vector
  is
    variable ret: std_ulogic_vector(0 to out_count_c-1);
  begin
    for i in ret'range
    loop
      ret(i) := to_logic(ethertype_l_c(i) = ethertype);
    end loop;

    return ret;
  end function;

  -- Output a match vector selects.  A binding table naming the same
  -- ethertype twice resolves to its last entry.
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
    -- Outcome of the comparisons the frame header feeds, kept apart
    -- from the output they select: the two take a cycle each.
    addressed: boolean;
    match: std_ulogic_vector(0 to out_count_c-1);
    drop: boolean;
    destination: natural range 0 to out_count_c-1;
    header: byte_string(0 to out_header_length_c-1);
  end record;

  signal r, rin: regs_t;

  signal route_valid_s, route_ready_s, route_drop_s: std_ulogic;
  signal route_in_header_s: byte_string(0 to in_header_length_c-1);
  signal route_out_header_s: byte_string(0 to out_header_length_c-1);
  signal route_destination_s: natural range 0 to out_count_c-1;
  signal route_source_s: natural range 0 to 0;

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_RESET;
    end if;
  end process;

  transition: process(r, local_address_i, route_valid_s, route_in_header_s) is
    variable da_v, sa_v: mac48_t;
    variable ethertype_v: ethertype_t;
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_IDLE;

      when ST_IDLE =>
        if route_valid_s = '1' then
          da_v := route_in_header_s(da_offset_c to da_offset_c+5);
          sa_v := route_in_header_s(sa_offset_c to sa_offset_c+5);
          ethertype_v := to_integer(from_be(route_in_header_s(et_offset_c to et_offset_c+1)));

          -- A broadcast frame is addressed to everyone, any other one
          -- has to name the local address.
          rin.state <= ST_DECIDE;
          rin.header <= route_in_header_s(0 to pre_size_c-1)
                        & context_pad(config_c,
                                      to_bytes(l2_context_t'(peer => sa_v,
                                                             casting => casting_of(da_v))));
          rin.addressed <= is_broadcast(da_v) or da_v = local_address_i;
          rin.match <= ethertype_match(ethertype_v);
        end if;

      when ST_DECIDE =>
        rin.state <= ST_RESPOND;
        rin.destination <= match_index(r.match);
        rin.drop <= not (r.addressed and match_any(r.match));

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

      in_i(0) => in_i,
      in_o(0) => in_o,

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
