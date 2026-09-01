library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_math, work;
use nsl_amba.axi4_stream.all;
use nsl_math.int_ext.all;
use work.ipv4.all;

entity stream_udp_layer is
  generic(
    config_c : config_t;
    header_length_c : integer_vector := null_integer_vector;
    udp_port_c : integer_vector
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    local_address_i : in ipv4_t;

    to_app_o : out master_vector(0 to udp_port_c'length-1);
    to_app_i : in slave_vector(0 to udp_port_c'length-1);
    from_app_i : in master_vector(0 to udp_port_c'length-1);
    from_app_o : out slave_vector(0 to udp_port_c'length-1);

    to_l4_o : out master_t;
    to_l4_i : in slave_t;
    from_l4_i : in master_t;
    from_l4_o : out slave_t
    );
end entity;

architecture beh of stream_udp_layer is

begin

  receiver: work.stream_udp.stream_udp_receiver
    generic map(
      config_c => config_c,
      header_length_c => header_length_c,
      udp_port_c => udp_port_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      local_address_i => local_address_i,

      in_i => from_l4_i,
      in_o => from_l4_o,

      out_o => to_app_o,
      out_i => to_app_i
      );

  transmitter: work.stream_udp.stream_udp_transmitter
    generic map(
      config_c => config_c,
      header_length_c => header_length_c,
      udp_port_c => udp_port_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      in_i => from_app_i,
      in_o => from_app_o,

      out_o => to_l4_o,
      out_i => to_l4_i
      );

end architecture;
