library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_logic, nsl_math, work;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_logic.bool.all;
use nsl_math.int_ext.all;
use work.stream.all;
use work.stream_ipv4.all;
use work.stream_udp.all;

entity stream_udp_transmitter is
  generic(
    config_c : config_t;
    header_length_c : integer_vector := null_integer_vector;
    udp_port_c : integer_vector
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    in_i : in master_vector(0 to udp_port_c'length-1);
    in_o : out slave_vector(0 to udp_port_c'length-1);

    out_o : out master_t;
    out_i : in slave_t
    );
end entity;

architecture beh of stream_udp_transmitter is

  constant in_count_c : natural := udp_port_c'length;
  constant lengths_c : integer_vector(0 to header_length_c'length-1)
    := header_length_c;
  constant port_l_c : integer_vector(0 to in_count_c-1) := udp_port_c;
  -- Transported size of the blocks forwarded verbatim, preceding the
  -- context block on the application side and the UDP header on the
  -- IPv4 side.
  constant pre_size_c : integer
    := context_byte_count(config_c, header_length_c);
  constant ip_context_block_c : integer
    := context_byte_count(config_c, (0 => ip_context_length_c));
  -- The IPv4 context is the last of the forwarded blocks, so it
  -- starts one block short of the end of the prefix.
  constant ip_context_offset_c : integer := pre_size_c - ip_context_block_c;
  constant context_block_c : integer
    := context_byte_count(config_c, (0 => udp_context_length_c));
  constant in_header_length_c : integer := pre_size_c + context_block_c;
  constant out_header_length_c : integer := pre_size_c + udp_header_length_c;

  -- The checksum of a datagram this layer sends is left out: over
  -- IPv4 a zero field means the sender computed none.
  constant no_checksum_c : byte_string(0 to 1) := (others => x"00");

  -- Elasticity absorbing the routing decision and the emission of
  -- the response header without stalling the input: response header
  -- beats plus arbitration and decision latency.
  constant fifo_depth_c : natural
    := out_header_length_c / config_c.data_width + 8;

  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_RESPOND
    );

  type regs_t is
  record
    state: state_t;
    header: byte_string(0 to out_header_length_c-1);
  end record;

  signal r, rin: regs_t;

  signal route_valid_s, route_ready_s: std_ulogic;
  signal route_in_header_s: byte_string(0 to in_header_length_c-1);
  signal route_out_header_s: byte_string(0 to out_header_length_c-1);
  signal route_source_s: natural range 0 to in_count_c-1;

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

  transition: process(r, route_valid_s, route_in_header_s, route_source_s) is
    variable context_v: udp_context_t;
    variable ip_context_v: ip_context_t;
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_IDLE;

      when ST_IDLE =>
        if route_valid_s = '1' then
          context_v := from_bytes(route_in_header_s(pre_size_c
                                                    to pre_size_c
                                                    + udp_context_length_c-1));
          -- Datagram length comes from the sibling IPv4 context the
          -- application filled in, it is not recomputed here.
          ip_context_v := from_bytes(route_in_header_s(ip_context_offset_c
                                                       to ip_context_offset_c
                                                       + ip_context_length_c-1));

          -- Header fields are independent of one another, they are
          -- laid out side by side rather than filled in one by one.
          rin.state <= ST_RESPOND;
          rin.header <= route_in_header_s(0 to pre_size_c-1)
                        & to_be(to_unsigned(port_l_c(route_source_s), 16))
                        & to_be(to_unsigned(context_v.peer_port, 16))
                        & to_be(to_unsigned(ip_context_v.length, 16))
                        & no_checksum_c;
        end if;

      when ST_RESPOND =>
        rin.state <= ST_IDLE;
    end case;
  end process;

  moore: process(r) is
  begin
    route_ready_s <= to_logic(r.state = ST_RESPOND);
    route_out_header_s <= r.header;
  end process;

  router: nsl_amba.stream_routing.axi4_stream_router
    generic map(
      config_c => config_c,
      in_count_c => in_count_c,
      out_count_c => 1,
      in_header_length_c => in_header_length_c,
      out_header_length_c => out_header_length_c,
      fifo_depth_c => fifo_depth_c
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i => clock_i,

      in_i => in_i,
      in_o => in_o,

      out_o(0) => out_o,
      out_i(0) => out_i,

      route_valid_o => route_valid_s,
      route_header_o => route_in_header_s,
      route_source_o => route_source_s,

      route_ready_i => route_ready_s,
      route_header_i => route_out_header_s,
      route_destination_i => 0,
      route_drop_i => '0'
      );

end architecture;
