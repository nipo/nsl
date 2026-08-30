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

entity stream_ipv4_transmitter is
  generic(
    config_c : config_t;
    header_length_c : integer_vector := null_integer_vector;
    ip_proto_c : ip_proto_vector;
    ttl_c : integer range 0 to 255 := 64
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    local_address_i : in ipv4_t;

    in_i : in master_vector(0 to ip_proto_c'length-1);
    in_o : out slave_vector(0 to ip_proto_c'length-1);

    out_o : out master_t;
    out_i : in slave_t
    );
end entity;

architecture beh of stream_ipv4_transmitter is

  constant in_count_c : natural := ip_proto_c'length;
  -- Transported size of the blocks forwarded verbatim, preceding the
  -- context block on the layer-4 side and the IPv4 header on the
  -- ethernet side.
  constant pre_size_c : natural
    := context_byte_count(config_c, header_length_c);
  constant context_block_c : natural
    := context_byte_count(config_c, (0 => ip_context_length_c));
  constant in_header_length_c : natural := pre_size_c + context_block_c;
  constant out_header_length_c : natural := pre_size_c + ipv4_header_length_c;
  constant ip_proto_l_c : ip_proto_vector(0 to in_count_c-1) := ip_proto_c;

  -- Header bytes folded into the checksum accumulator per cycle.
  -- Must be even and must divide the header length, so that every
  -- chunk is a whole count of 16-bit words starting on a 16-bit
  -- boundary of the header.  A chunk is one add-with-carry, this is
  -- the knob trading decision latency for that adder's width.
  constant fold_chunk_c : natural := 4;
  constant fold_steps_c : natural := ipv4_header_length_c / fold_chunk_c;
  constant checksum_c : checksum_config_t := checksum_config(fold_chunk_c);

  -- Cycles from the routing request to the response: header craft,
  -- checksum fold, checksum spill and response.
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
    ST_SPILL,
    ST_RESPOND
    );

  type regs_t is
  record
    state: state_t;
    identification: unsigned(15 downto 0);
    header: byte_string(0 to out_header_length_c-1);
    acc: checksum_state_t;
    fold_index: natural range 0 to fold_steps_c-1;
  end record;

  signal r, rin: regs_t;

  signal route_valid_s, route_ready_s: std_ulogic;
  signal route_in_header_s: byte_string(0 to in_header_length_c-1);
  signal route_out_header_s: byte_string(0 to out_header_length_c-1);
  signal route_source_s: natural range 0 to in_count_c-1;

  -- Header bytes the fold step at hand covers.  The crafted header is
  -- already registered, it is walked in place rather than copied.
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

  -- Wire format of the header this layer crafts.  Fields the layer
  -- never varies are constant here, and the checksum field is left
  -- clear so that the fold below covers it as such.  Concatenation is
  -- no help writing this: an ipv4_t is a byte_string, so every "&"
  -- joining two of them is ambiguous with the ipv4_vector one.
  function ipv4_header(total: integer;
                       identification: unsigned;
                       proto: ip_proto_t;
                       source, destination: ipv4_t) return byte_string
  is
    variable ret: byte_string(0 to ipv4_header_length_c-1) := (others => x"00");
  begin
    ret(ip_off_type_len) := x"45";
    ret(ip_off_len_h to ip_off_len_l) := to_be(to_unsigned(total, 16));
    ret(ip_off_id_h to ip_off_id_l) := to_be(identification);
    -- Don't fragment, no fragment offset
    ret(ip_off_off_h) := x"40";
    ret(ip_off_ttl) := to_byte(ttl_c);
    ret(ip_off_proto) := to_byte(proto);
    ret(ip_off_src0 to ip_off_src3) := source;
    ret(ip_off_dst0 to ip_off_dst3) := destination;
    return ret;
  end function;

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_RESET;
      r.identification <= (others => '0');
    end if;
  end process;

  transition: process(r, local_address_i, route_valid_s, route_in_header_s,
                      route_source_s) is
    variable context_v: ip_context_t;
    variable header_v: byte_string(0 to ipv4_header_length_c-1);
    variable chunk_v: byte_string(0 to fold_chunk_c-1);
    variable acc_v: checksum_state_t;
  begin
    rin <= r;

    chunk_v := fold_slice(r.header, r.fold_index);
    acc_v := checksum_update(checksum_c, r.acc, chunk_v);

    case r.state is
      when ST_RESET =>
        rin.state <= ST_IDLE;

      when ST_IDLE =>
        if route_valid_s = '1' then
          context_v := from_bytes(route_in_header_s(pre_size_c
                                                    to pre_size_c
                                                    + ip_context_length_c-1));

          header_v := ipv4_header(context_v.length + ipv4_header_length_c,
                                  r.identification,
                                  ip_proto_l_c(route_source_s),
                                  local_address_i,
                                  context_v.peer);

          rin.state <= ST_FOLD;
          rin.fold_index <= 0;
          rin.acc <= checksum_init(checksum_c);
          rin.identification <= r.identification + 1;
          rin.header <= route_in_header_s(0 to pre_size_c-1) & header_v;
        end if;

      -- The checksum field is still zero in the registered header,
      -- folding it in costs nothing.
      when ST_FOLD =>
        rin.acc <= acc_v;

        if r.fold_index = fold_steps_c-1 then
          rin.state <= ST_SPILL;
        else
          rin.fold_index <= r.fold_index + 1;
        end if;

      -- The accumulator holds the complement of the sum, which is
      -- what the checksum field carries.
      when ST_SPILL =>
        rin.header(pre_size_c + ip_off_chk_h to pre_size_c + ip_off_chk_l)
          <= checksum_spill(checksum_c, r.acc);
        rin.state <= ST_RESPOND;

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
