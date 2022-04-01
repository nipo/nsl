library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_data, nsl_inet, nsl_math;
use nsl_inet.ethernet.all;
use nsl_bnoc.committed.all;
use nsl_bnoc.framed.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_inet.udp.all;

entity udp_layer is
  generic(
    tx_mtu_c : integer := 1500;
    udp_port_c : udp_port_vector;
    header_length_c : integer
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    to_l5_o : out committed_req_array(0 to udp_port_c'length - 1);
    to_l5_i : in committed_ack_array(0 to udp_port_c'length - 1);
    from_l5_i : in committed_req_array(0 to udp_port_c'length - 1);
    from_l5_o : out committed_ack_array(0 to udp_port_c'length - 1);

    from_l3_i : in committed_req;
    from_l3_o : out committed_ack;
    to_l3_o : out committed_req;
    to_l3_i : in committed_ack
    );
end entity;

architecture beh of udp_layer is

  alias udp_port_l_c: udp_port_vector(0 to udp_port_c'length-1) is udp_port_c;

  signal to_l5_s, from_l5_s: committed_bus;

  signal to_l5_drop_s: std_ulogic;
  signal to_l5_destination_s : natural range 0 to udp_port_l_c'length-1;
  signal from_l5_source_s : natural range 0 to udp_port_l_c'length-1;

  signal to_l5_in_header_s : byte_string(0 to header_length_c+4-1);
  signal to_l5_out_header_s : byte_string(0 to header_length_c+2-1);
  signal from_l5_out_header_s : byte_string(0 to header_length_c+4-1);
  signal from_l5_in_header_s : byte_string(0 to header_length_c+2-1);
  
  signal s_to_l5_o : framed_req_array(0 to udp_port_l_c'length - 1);
  signal s_to_l5_i : framed_ack_array(0 to udp_port_l_c'length - 1);
  signal s_from_l5_i : framed_req_array(0 to udp_port_l_c'length - 1);
  signal s_from_l5_o : framed_ack_array(0 to udp_port_l_c'length - 1);

begin

  l5_map: for i in 0 to udp_port_l_c'length-1
  generate
    to_l5_o(i) <= s_to_l5_o(i);
    from_l5_o(i) <= s_from_l5_o(i);
    s_to_l5_i(i) <= to_l5_i(i);
    s_from_l5_i(i) <= from_l5_i(i);
  end generate;
  
  receiver: nsl_inet.udp.udp_receiver
    generic map(
      header_length_c => header_length_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      l3_i => from_l3_i,
      l3_o => from_l3_o,

      l5_o => to_l5_s.req,
      l5_i => to_l5_s.ack
      );
  
  to_l5_router: nsl_bnoc.framed.framed_router
    generic map(
      in_count_c => 1,
      out_count_c => udp_port_l_c'length,
      in_header_count_c => to_l5_in_header_s'length,
      out_header_count_c => to_l5_out_header_s'length
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      in_i(0) => to_l5_s.req,
      in_o(0) => to_l5_s.ack,
      
      out_o => s_to_l5_o,
      out_i => s_to_l5_i,

      route_header_o => to_l5_in_header_s,
      route_header_i => to_l5_out_header_s,
      route_ready_i => '1',
      route_destination_i => to_l5_destination_s,
      route_drop_i => to_l5_drop_s
      );

  to_l5_route: process(to_l5_in_header_s) is
    variable local_port: udp_port_t;
  begin
    to_l5_drop_s <= '1';
    to_l5_destination_s <= 0;
    to_l5_out_header_s <= to_l5_in_header_s(to_l5_out_header_s'range);

    local_port := to_integer(from_be(
      to_l5_in_header_s(to_l5_in_header_s'right-1 to to_l5_in_header_s'right)
      ));
    
    for i in udp_port_l_c'range
    loop
      if udp_port_l_c(i) = local_port then
        to_l5_drop_s <= '0';
        to_l5_destination_s <= i;
      end if;
    end loop;
  end process;
  
  from_l5_router: nsl_bnoc.framed.framed_router
    generic map(
      in_count_c => udp_port_l_c'length,
      out_count_c => 1,
      in_header_count_c => from_l5_in_header_s'length,
      out_header_count_c => from_l5_out_header_s'length
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      
      in_i => s_from_l5_i,
      in_o => s_from_l5_o,

      out_o(0) => from_l5_s.req,
      out_i(0) => from_l5_s.ack,

      route_source_o => from_l5_source_s,

      route_ready_i => '1',
      route_header_o => from_l5_in_header_s,
      route_header_i => from_l5_out_header_s,
      route_destination_i => 0,
      route_drop_i => '0'
      );

  from_l5_route: process(from_l5_in_header_s, from_l5_source_s) is
  begin
    from_l5_out_header_s <= from_l5_in_header_s
                            & to_be(to_unsigned(udp_port_l_c(from_l5_source_s), 16));
  end process;
  
  transmitter: nsl_inet.udp.udp_transmitter
    generic map(
      mtu_c => tx_mtu_c,
      header_length_c => header_length_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      l5_i => from_l5_s.req,
      l5_o => from_l5_s.ack,

      l3_o => to_l3_o,
      l3_i => to_l3_i
      );

end architecture;
