library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_math, work;
use nsl_amba.axi4_stream.all;
use nsl_math.int_ext.all;
use work.ipv4.all;

entity stream_ipv4_layer is
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

    to_l4_o : out master_vector(0 to ip_proto_c'length-1);
    to_l4_i : in slave_vector(0 to ip_proto_c'length-1);
    from_l4_i : in master_vector(0 to ip_proto_c'length-1);
    from_l4_o : out slave_vector(0 to ip_proto_c'length-1);

    to_l3_o : out master_t;
    to_l3_i : in slave_t;
    from_l3_i : in master_t;
    from_l3_o : out slave_t
    );
end entity;

architecture beh of stream_ipv4_layer is

begin

  receiver: work.stream_ipv4.stream_ipv4_receiver
    generic map(
      config_c => config_c,
      header_length_c => header_length_c,
      ip_proto_c => ip_proto_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      local_address_i => local_address_i,

      in_i => from_l3_i,
      in_o => from_l3_o,

      out_o => to_l4_o,
      out_i => to_l4_i
      );

  transmitter: work.stream_ipv4.stream_ipv4_transmitter
    generic map(
      config_c => config_c,
      header_length_c => header_length_c,
      ip_proto_c => ip_proto_c,
      ttl_c => ttl_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      local_address_i => local_address_i,

      in_i => from_l4_i,
      in_o => from_l4_o,

      out_o => to_l3_o,
      out_i => to_l3_i
      );

end architecture;
