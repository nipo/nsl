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
use work.vlan.all;
use work.stream_vlan.all;

-- Tagged pipes go through a router that peels the untagged header and
-- emits the tagged one, the VID being a function of the source port.
-- The native pipe, if any, needs no rewrite and joins the router
-- output through a funnel.
entity stream_vlan_mux is
  generic(
    config_c : config_t;
    header_length_c : integer_vector := null_integer_vector;
    vlan_id_c : vlan_id_vector;
    native_vlan_id_c : vlan_id_t := 0
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    in_i : in master_vector(0 to vlan_id_c'length-1);
    in_o : out slave_vector(0 to vlan_id_c'length-1);

    out_o : out master_t;
    out_i : in slave_t
    );
end entity;

architecture beh of stream_vlan_mux is

  constant in_count_c : natural := vlan_id_c'length;
  constant vlan_id_l_c : vlan_id_vector(0 to in_count_c-1) := vlan_id_c;
  constant native_index_c : integer := vlan_index(vlan_id_l_c, native_vlan_id_c);

  -- Pipes needing a tag, i.e. every pipe but the native one
  constant tagged_count_c : natural
    := in_count_c - if_else(native_index_c >= 0, 1, 0);

  -- Pipe index of each router input
  function tagged_pipe_list return integer_vector
  is
    variable ret: integer_vector(0 to tagged_count_c-1);
    variable j: natural := 0;
  begin
    for i in 0 to in_count_c-1
    loop
      if i /= native_index_c then
        ret(j) := i;
        j := j + 1;
      end if;
    end loop;
    return ret;
  end function;

  constant tagged_pipe_c : integer_vector(0 to tagged_count_c-1)
    := tagged_pipe_list;

  constant pre_size_c : natural
    := context_byte_count(config_c, header_length_c);
  constant untagged_header_length_c : natural
    := pre_size_c + ethernet_frame_offset(config_c) + ethernet_header_length_c;
  constant tagged_header_length_c : natural
    := untagged_header_length_c + vlan_tag_length_c;
  constant type_offset_c : natural := untagged_header_length_c - 2;

  constant tpid_c : byte_string(0 to 1)
    := to_be(to_unsigned(ethertype_vlan, 16));

begin

  native_only: if tagged_count_c = 0
  generate
    out_o <= in_i(native_index_c);
    in_o(native_index_c) <= out_i;
  end generate;

  tagging: if tagged_count_c /= 0
  generate
    type state_t is (
      ST_RESET,
      ST_IDLE,
      ST_RESPOND
      );

    type regs_t is
    record
      state: state_t;
      header: byte_string(0 to tagged_header_length_c-1);
    end record;

    signal r, rin: regs_t;

    signal tagged_in_m_s : master_vector(0 to tagged_count_c-1);
    signal tagged_in_s_s : slave_vector(0 to tagged_count_c-1);
    signal tagged_out_s : bus_t;

    signal route_valid_s, route_ready_s: std_ulogic;
    signal route_in_header_s: byte_string(0 to untagged_header_length_c-1);
    signal route_out_header_s: byte_string(0 to tagged_header_length_c-1);
    signal route_source_s: natural range 0 to tagged_count_c-1;
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

    transition: process(r, route_valid_s, route_in_header_s,
                        route_source_s) is
      variable vid_v: vlan_id_t;
    begin
      rin <= r;

      case r.state is
        when ST_RESET =>
          rin.state <= ST_IDLE;

        when ST_IDLE =>
          if route_valid_s = '1' then
            vid_v := vlan_id_l_c(tagged_pipe_c(route_source_s));
            rin.state <= ST_RESPOND;
            rin.header <= route_in_header_s(0 to type_offset_c-1)
                          & tpid_c
                          & to_be(to_unsigned(vid_v, 16))
                          & route_in_header_s(type_offset_c
                                              to type_offset_c+1);
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

    ports: for j in 0 to tagged_count_c-1
    generate
      tagged_in_m_s(j) <= in_i(tagged_pipe_c(j));
      in_o(tagged_pipe_c(j)) <= tagged_in_s_s(j);
    end generate;

    router: nsl_amba.stream_routing.axi4_stream_router
      generic map(
        config_c => config_c,
        in_count_c => tagged_count_c,
        out_count_c => 1,
        in_header_length_c => untagged_header_length_c,
        out_header_length_c => tagged_header_length_c,
        fifo_depth_c => 16
        )
      port map(
        reset_n_i => reset_n_i,
        clock_i => clock_i,

        in_i => tagged_in_m_s,
        in_o => tagged_in_s_s,

        out_o(0) => tagged_out_s.m,
        out_i(0) => tagged_out_s.s,

        route_valid_o => route_valid_s,
        route_header_o => route_in_header_s,
        route_source_o => route_source_s,

        route_ready_i => route_ready_s,
        route_header_i => route_out_header_s,
        route_destination_i => 0,
        route_drop_i => '0'
        );

    no_native: if native_index_c < 0
    generate
      out_o <= tagged_out_s.m;
      tagged_out_s.s <= out_i;
    end generate;

    with_native: if native_index_c >= 0
    generate
      funnel: nsl_amba.stream_routing.axi4_stream_funnel
        generic map(
          in_config_c => config_c,
          out_config_c => config_c,
          source_count_c => 2
          )
        port map(
          clock_i => clock_i,
          reset_n_i => reset_n_i,

          in_i(0) => tagged_out_s.m,
          in_i(1) => in_i(native_index_c),
          in_o(0) => tagged_out_s.s,
          in_o(1) => in_o(native_index_c),

          out_o => out_o,
          out_i => out_i
          );
    end generate;
  end generate;

end architecture;
