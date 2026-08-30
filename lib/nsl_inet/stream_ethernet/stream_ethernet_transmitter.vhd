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

entity stream_ethernet_transmitter is
  generic(
    config_c : config_t;
    header_length_c : integer_vector := null_integer_vector;
    ethertype_c : ethertype_vector
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    local_address_i : in mac48_t;

    in_i : in master_vector(0 to ethertype_c'length-1);
    in_o : out slave_vector(0 to ethertype_c'length-1);

    out_o : out master_t;
    out_i : in slave_t
    );
end entity;

architecture beh of stream_ethernet_transmitter is

  constant in_count_c : natural := ethertype_c'length;
  -- Transported size of the blocks forwarded verbatim, preceding the
  -- context block on the layer-3 side and the ethernet frame block on
  -- the mac side.
  constant pre_size_c : natural
    := context_byte_count(config_c, header_length_c);
  constant frame_offset_c : natural := ethernet_frame_offset(config_c);
  constant frame_block_c : natural
    := frame_offset_c + ethernet_header_length_c;
  constant context_block_c : natural
    := context_byte_count(config_c, (0 => l2_context_length_c));
  constant in_header_length_c : natural := pre_size_c + context_block_c;
  constant out_header_length_c : natural := pre_size_c + frame_block_c;
  constant frame_pad_c : byte_string(0 to frame_offset_c-1) := (others => x"00");
  constant ethertype_l_c : ethertype_vector(0 to in_count_c-1) := ethertype_c;

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

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_RESET;
    end if;
  end process;

  transition: process(r, local_address_i, route_valid_s, route_in_header_s,
                      route_source_s) is
    variable context_v: l2_context_t;
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_IDLE;

      when ST_IDLE =>
        if route_valid_s = '1' then
          context_v := from_bytes(route_in_header_s(pre_size_c
                                                    to pre_size_c
                                                    + l2_context_length_c-1));

          rin.state <= ST_RESPOND;
          rin.header <= route_in_header_s(0 to pre_size_c-1)
                        & frame_pad_c
                        & context_v.peer
                        & local_address_i
                        & to_be(to_unsigned(ethertype_l_c(route_source_s), 16));
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
      fifo_depth_c => 16
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
