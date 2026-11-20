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

-- Two routing stages, each with a fixed header geometry:
--
-- * the untagged stage, present only when the native VID is
--   configured, peels the untagged header, sends untagged frames to
--   the native pipe as they came and tagged ones to the tagged stage;
--
-- * the tagged stage peels the tagged header, drops untagged frames
--   (which only reach it when there is no untagged stage), looks the
--   VID up and hands the frame to its pipe with the tag removed.
--
-- The native pipe merges both sources through a funnel.
entity stream_vlan_demux is
  generic(
    config_c : config_t;
    header_length_c : integer_vector := null_integer_vector;
    vlan_id_c : vlan_id_vector;
    native_vlan_id_c : vlan_id_t := 0
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    in_i : in master_t;
    in_o : out slave_t;

    out_o : out master_vector(0 to vlan_id_c'length-1);
    out_i : in slave_vector(0 to vlan_id_c'length-1)
    );
end entity;

architecture beh of stream_vlan_demux is

  constant out_count_c : natural := vlan_id_c'length;
  constant vlan_id_l_c : vlan_id_vector(0 to out_count_c-1) := vlan_id_c;
  constant native_index_c : integer := vlan_index(vlan_id_l_c, native_vlan_id_c);

  constant pre_size_c : natural
    := context_byte_count(config_c, header_length_c);
  constant untagged_header_length_c : natural
    := pre_size_c + ethernet_frame_offset(config_c) + ethernet_header_length_c;
  constant tagged_header_length_c : natural
    := untagged_header_length_c + vlan_tag_length_c;
  -- Offset of the ethertype field of an untagged frame, i.e. of the
  -- TPID of a tagged one
  constant tpid_offset_c : natural := untagged_header_length_c - 2;
  constant tci_offset_c : natural := tpid_offset_c + 2;
  constant inner_type_offset_c : natural := tci_offset_c + 2;

  -- Elasticity absorbing the routing decision and the emission of the
  -- response header without stalling the input, as for the ethernet
  -- receiver.
  constant tagged_decide_latency_c : natural := 3;
  constant tagged_fifo_depth_c : natural
    := untagged_header_length_c / config_c.data_width
    + tagged_decide_latency_c + 7;
  -- The untagged stage also absorbs the lag of the tagged stage: an
  -- untagged frame following a frame tagged with the native VID waits
  -- at the native funnel for the latter to leave the tagged stage.
  constant untagged_fifo_depth_c : natural
    := untagged_header_length_c / config_c.data_width + 1 + 7
    + tagged_header_length_c / config_c.data_width + tagged_fifo_depth_c;

  function is_tagged(header: byte_string) return boolean
  is
  begin
    return to_integer(from_be(header(tpid_offset_c to tpid_offset_c+1)))
      = ethertype_vlan;
  end function;

  function vid_match(header: byte_string) return std_ulogic_vector
  is
    constant tci_c : unsigned(15 downto 0)
      := from_be(header(tci_offset_c to tci_offset_c+1));
    constant vid_c : vlan_id_t := to_integer(tci_c(11 downto 0));
    variable ret: std_ulogic_vector(0 to out_count_c-1);
  begin
    for i in ret'range
    loop
      ret(i) := to_logic(vlan_id_l_c(i) = vid_c);
    end loop;
    return ret;
  end function;

  -- First matching pipe, so that a VID listed twice resolves like
  -- vlan_index() does.
  function match_index(match: std_ulogic_vector) return natural
  is
    variable ret: natural range 0 to out_count_c-1 := 0;
  begin
    for i in match'reverse_range
    loop
      if match(i) = '1' then
        ret := i;
      end if;
    end loop;
    return ret;
  end function;

  function match_any(match: std_ulogic_vector) return boolean
  is
    variable ret: std_ulogic := '0';
  begin
    for i in match'range
    loop
      ret := ret or match(i);
    end loop;
    return ret = '1';
  end function;

  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_DECIDE,
    ST_RESPOND
    );

  type regs_t is
  record
    state: state_t;
    -- VID lookup and the output it selects take a cycle each
    tagged: boolean;
    match: std_ulogic_vector(0 to out_count_c-1);
    drop: boolean;
    destination: natural range 0 to out_count_c-1;
    header: byte_string(0 to untagged_header_length_c-1);
  end record;

  signal r, rin: regs_t;

  signal tagged_in_s : bus_t;
  signal tagged_out_m_s : master_vector(0 to out_count_c-1);
  signal tagged_out_s_s : slave_vector(0 to out_count_c-1);

  signal route_valid_s, route_ready_s, route_drop_s: std_ulogic;
  signal route_in_header_s: byte_string(0 to tagged_header_length_c-1);
  signal route_out_header_s: byte_string(0 to untagged_header_length_c-1);
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

  transition: process(r, route_valid_s, route_in_header_s) is
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_IDLE;

      when ST_IDLE =>
        if route_valid_s = '1' then
          rin.state <= ST_DECIDE;
          rin.header <= route_in_header_s(0 to tpid_offset_c-1)
                        & route_in_header_s(inner_type_offset_c
                                            to inner_type_offset_c+1);
          rin.tagged <= is_tagged(route_in_header_s);
          rin.match <= vid_match(route_in_header_s);
        end if;

      when ST_DECIDE =>
        rin.state <= ST_RESPOND;
        rin.destination <= match_index(r.match);
        rin.drop <= not (r.tagged and match_any(r.match));

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

  tagged_router: nsl_amba.stream_routing.axi4_stream_router
    generic map(
      config_c => config_c,
      in_count_c => 1,
      out_count_c => out_count_c,
      in_header_length_c => tagged_header_length_c,
      out_header_length_c => untagged_header_length_c,
      fifo_depth_c => tagged_fifo_depth_c
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i => clock_i,

      in_i(0) => tagged_in_s.m,
      in_o(0) => tagged_in_s.s,

      out_o => tagged_out_m_s,
      out_i => tagged_out_s_s,

      route_valid_o => route_valid_s,
      route_header_o => route_in_header_s,
      route_source_o => route_source_s,

      route_ready_i => route_ready_s,
      route_header_i => route_out_header_s,
      route_destination_i => route_destination_s,
      route_drop_i => route_drop_s
      );

  no_native: if native_index_c < 0
  generate
    -- Untagged frames reach the tagged stage, which drops them.
    tagged_in_s.m <= in_i;
    in_o <= tagged_in_s.s;

    pipes: for i in 0 to out_count_c-1
    generate
      out_o(i) <= tagged_out_m_s(i);
      tagged_out_s_s(i) <= out_i(i);
    end generate;
  end generate;

  with_native: if native_index_c >= 0
  generate
    -- Untagged stage outputs
    constant UNTAGGED_NATIVE : natural := 0;
    constant UNTAGGED_TAGGED : natural := 1;

    signal untagged_out_m_s : master_vector(0 to 1);
    signal untagged_out_s_s : slave_vector(0 to 1);
    signal untagged_valid_s : std_ulogic;
    signal untagged_header_s : byte_string(0 to untagged_header_length_c-1);
    signal untagged_destination_s : natural range 0 to 1;
    signal untagged_source_s : natural range 0 to 0;
    signal native_s : bus_t;
  begin

    -- A single comparison on a header register of the router: the
    -- decision is answered on the request cycle, the header goes back
    -- unchanged.
    untagged_destination_s <= UNTAGGED_TAGGED
                              when is_tagged(untagged_header_s)
                              else UNTAGGED_NATIVE;

    untagged_router: nsl_amba.stream_routing.axi4_stream_router
      generic map(
        config_c => config_c,
        in_count_c => 1,
        out_count_c => 2,
        in_header_length_c => untagged_header_length_c,
        out_header_length_c => untagged_header_length_c,
        fifo_depth_c => untagged_fifo_depth_c
        )
      port map(
        reset_n_i => reset_n_i,
        clock_i => clock_i,

        in_i(0) => in_i,
        in_o(0) => in_o,

        out_o => untagged_out_m_s,
        out_i => untagged_out_s_s,

        route_valid_o => untagged_valid_s,
        route_header_o => untagged_header_s,
        route_source_o => untagged_source_s,

        route_ready_i => '1',
        route_header_i => untagged_header_s,
        route_destination_i => untagged_destination_s,
        route_drop_i => '0'
        );

    tagged_in_s.m <= untagged_out_m_s(UNTAGGED_TAGGED);
    untagged_out_s_s(UNTAGGED_TAGGED) <= tagged_in_s.s;

    native_funnel: nsl_amba.stream_routing.axi4_stream_funnel
      generic map(
        in_config_c => config_c,
        out_config_c => config_c,
        source_count_c => 2
        )
      port map(
        clock_i => clock_i,
        reset_n_i => reset_n_i,

        in_i(0) => untagged_out_m_s(UNTAGGED_NATIVE),
        in_i(1) => tagged_out_m_s(native_index_c),
        in_o(0) => untagged_out_s_s(UNTAGGED_NATIVE),
        in_o(1) => tagged_out_s_s(native_index_c),

        out_o => native_s.m,
        out_i => native_s.s
        );

    pipes: for i in 0 to out_count_c-1
    generate
      native: if i = native_index_c
      generate
        out_o(i) <= native_s.m;
        native_s.s <= out_i(i);
      end generate;

      other: if i /= native_index_c
      generate
        out_o(i) <= tagged_out_m_s(i);
        tagged_out_s_s(i) <= out_i(i);
      end generate;
    end generate;
  end generate;

end architecture;
