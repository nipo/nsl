library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_logic, nsl_math, work;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_logic.bool.all;
use nsl_math.int_ext.all;
use work.checksum.all;
use work.ipv4.all;
use work.stream.all;
use work.stream_ipv4.all;

entity stream_ipv4_receiver is
  generic(
    config_c : config_t;
    header_length_c : integer_vector := null_integer_vector;
    ip_proto_c : ip_proto_vector
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    local_address_i : in ipv4_t;

    in_i : in master_t;
    in_o : out slave_t;

    out_o : out master_vector(0 to ip_proto_c'length-1);
    out_i : in slave_vector(0 to ip_proto_c'length-1)
    );
end entity;

architecture beh of stream_ipv4_receiver is

  constant out_count_c : natural := ip_proto_c'length;
  -- Transported size of the blocks forwarded verbatim, preceding the
  -- IPv4 header on the ethernet side and the context block on the
  -- layer-4 side.
  constant pre_size_c : natural
    := context_byte_count(config_c, header_length_c);
  constant context_block_c : natural
    := context_byte_count(config_c, (0 => ip_context_length_c));
  constant in_header_length_c : natural := pre_size_c + ipv4_header_length_c;
  constant out_header_length_c : natural := pre_size_c + context_block_c;
  constant ip_proto_l_c : ip_proto_vector(0 to out_count_c-1) := ip_proto_c;
  constant broadcast_c : ipv4_t := to_ipv4(255, 255, 255, 255);
  -- Fragment offset and more-fragments bits of the flags/offset
  -- field, the don't-fragment bit excluded.
  constant fragment_mask_h_c : byte := x"3f";

  -- Header bytes folded into the checksum accumulator per cycle.
  -- Must be even and must divide the header length, so that every
  -- chunk is a whole count of 16-bit words starting on a 16-bit
  -- boundary of the header.  A chunk is one add-with-carry, this is
  -- the knob trading decision latency for that adder's width.
  constant fold_chunk_c : natural := 4;
  constant fold_steps_c : natural := ipv4_header_length_c / fold_chunk_c;
  constant checksum_c : checksum_config_t := checksum_config(fold_chunk_c);

  -- Cycles from the routing request to the response: field decoding,
  -- checksum fold, verdict and response.
  constant decide_latency_c : natural := fold_steps_c + 3;

  -- Elasticity absorbing the routing decision and the emission of
  -- the response header without stalling the input: response header
  -- beats plus arbitration and decision latency.
  constant fifo_depth_c : natural
    := out_header_length_c / config_c.data_width + decide_latency_c + 6;

  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_FOLD,
    ST_CHECK,
    ST_RESPOND
    );

  type regs_t is
  record
    state: state_t;
    drop: boolean;
    -- Every acceptance criterion but the header checksum
    accepted: boolean;
    destination: natural range 0 to out_count_c-1;
    header: byte_string(0 to out_header_length_c-1);
    acc: checksum_state_t;
    fold_index: natural range 0 to fold_steps_c-1;
  end record;

  signal r, rin: regs_t;

  signal trimmed_s: bus_t;

  signal route_valid_s, route_ready_s, route_drop_s: std_ulogic;
  signal route_in_header_s: byte_string(0 to in_header_length_c-1);
  signal route_out_header_s: byte_string(0 to out_header_length_c-1);
  signal route_destination_s: natural range 0 to out_count_c-1;
  signal route_source_s: natural range 0 to 0;

  -- Header bytes the fold step at hand covers.  The router holds the
  -- extracted header until the response, it is walked in place rather
  -- than copied.
  function fold_slice(header: byte_string;
                      index: natural) return byte_string
  is
    alias h: byte_string(0 to header'length-1) is header;
    variable ret: byte_string(0 to fold_chunk_c-1) := (others => x"00");
  begin
    for i in 0 to fold_steps_c-1
    loop
      if index = i then
        ret := h(pre_size_c + i * fold_chunk_c
                 to pre_size_c + (i+1) * fold_chunk_c - 1);
      end if;
    end loop;
    return ret;
  end function;

  function casting_of(destination: ipv4_t) return ip_casting_t
  is
  begin
    if destination = broadcast_c then
      return IP_CAST_BROADCAST;
    else
      return IP_CAST_UNICAST;
    end if;
  end function;

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
    variable header_v: byte_string(0 to ipv4_header_length_c-1);
    variable source_v, destination_v: ipv4_t;
    variable casting_v: ip_casting_t;
    variable total_v, pdu_v: integer range 0 to 65535;
    variable proto_v: ip_proto_t;
    variable accepted_v: boolean;
    variable chunk_v: byte_string(0 to fold_chunk_c-1);
    variable acc_v: checksum_state_t;
  begin
    rin <= r;

    chunk_v := fold_slice(route_in_header_s, r.fold_index);
    acc_v := checksum_update(checksum_c, r.acc, chunk_v);

    case r.state is
      when ST_RESET =>
        rin.state <= ST_IDLE;

      when ST_IDLE =>
        if route_valid_s = '1' then
          header_v := route_in_header_s(pre_size_c
                                        to pre_size_c
                                        + ipv4_header_length_c-1);
          source_v := header_v(ip_off_src0 to ip_off_src3);
          destination_v := header_v(ip_off_dst0 to ip_off_dst3);
          total_v := to_integer(from_be(header_v(ip_off_len_h
                                                 to ip_off_len_l)));
          proto_v := to_integer(header_v(ip_off_proto));
          pdu_v := nsl_math.arith.max(0, total_v - ipv4_header_length_c);
          casting_v := casting_of(destination_v);
          -- A broadcast destination is taken whatever the local
          -- address; anything else has to match it.
          accepted_v := header_v(ip_off_type_len) = x"45"
                        and (header_v(ip_off_off_h)
                             and fragment_mask_h_c) = x"00"
                        and header_v(ip_off_off_l) = x"00"
                        and total_v >= ipv4_header_length_c
                        and (destination_v = broadcast_c
                             or destination_v = local_address_i);

          rin.state <= ST_FOLD;
          rin.fold_index <= 0;
          rin.acc <= checksum_init(checksum_c);
          rin.header <= route_in_header_s(0 to pre_size_c-1)
                        & context_pad(config_c,
                                      to_bytes(ip_context_t'(peer => source_v,
                                                             casting => casting_v,
                                                             length => pdu_v)));
          rin.destination <= 0;
          rin.accepted <= false;

          if accepted_v then
            for i in ip_proto_l_c'range
            loop
              if ip_proto_l_c(i) = proto_v then
                rin.destination <= i;
                rin.accepted <= true;
              end if;
            end loop;
          end if;
        end if;

      when ST_FOLD =>
        rin.acc <= acc_v;

        if r.fold_index = fold_steps_c-1 then
          rin.state <= ST_CHECK;
        else
          rin.fold_index <= r.fold_index + 1;
        end if;

      -- The header covers a whole count of 16-bit words, the
      -- accumulator finalizes to zero when its checksum verifies.
      when ST_CHECK =>
        rin.drop <= not (r.accepted and checksum_is_valid(checksum_c, r.acc));
        rin.state <= ST_RESPOND;

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

  -- Trimming happens before routing so that the mac padding is gone
  -- from the payload the router forwards.  The minimum cut keeps the
  -- header the router extracts whole whatever the length field says.
  trimmer: work.stream_ipv4.stream_ipv4_trimmer
    generic map(
      config_c => config_c,
      length_offset_c => pre_size_c + ip_off_len_h,
      prefix_length_c => pre_size_c,
      min_length_c => pre_size_c + ipv4_header_length_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      in_i => in_i,
      in_o => in_o,

      out_o => trimmed_s.m,
      out_i => trimmed_s.s
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

      in_i(0) => trimmed_s.m,
      in_o(0) => trimmed_s.s,

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
