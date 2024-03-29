library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_data, work, nsl_math;
use work.ethernet.all;
use nsl_bnoc.committed.all;
use nsl_bnoc.framed.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use work.ipv4.all;

entity ipv4_layer is
  generic(
    header_length_c : integer := 0;
    ttl_c : integer := 64;
    ip_proto_c : ip_proto_vector;
    mtu_c: integer := 1500
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    unicast_i : in ipv4_t;
    broadcast_i : in ipv4_t;

    to_l4_o : out committed_req_array(0 to ip_proto_c'length-1);
    to_l4_i : in committed_ack_array(0 to ip_proto_c'length-1);
    from_l4_i : in committed_req_array(0 to ip_proto_c'length-1);
    from_l4_o : out committed_ack_array(0 to ip_proto_c'length-1);

    to_l2_o : out committed_req;
    to_l2_i : in committed_ack;
    from_l2_i : in committed_req;
    from_l2_o : out committed_ack
    );
end entity;

architecture beh of ipv4_layer is

  constant icmp_singleton : ip_proto_vector(0 to 0) := (others => ip_proto_icmp);
  constant ip_proto_l_c : ip_proto_vector(0 to ip_proto_c'length)
    := ip_proto_c & icmp_singleton;
  
  signal to_l4_s, from_l4_s, to_transmit_s: committed_bus;
  signal to_l4_req_s : framed_req_array(0 to ip_proto_l_c'length-1);
  signal to_l4_ack_s : framed_ack_array(0 to ip_proto_l_c'length-1);
  signal from_l4_req_s : framed_req_array(0 to ip_proto_l_c'length-1);
  signal from_l4_ack_s : framed_ack_array(0 to ip_proto_l_c'length-1);

  signal to_l4_drop_s: std_ulogic;
  signal to_l4_in_header_s, from_l4_out_header_s : byte_string(0 to header_length_c+6-1);
  signal to_l4_out_header_s, from_l4_in_header_s : byte_string(0 to header_length_c+5-1);
    
  signal to_l4_destination_s : natural range 0 to ip_proto_l_c'length-1;
  signal from_l4_source_s : natural range 0 to ip_proto_l_c'length-1;
  
begin
  
  l4_map: for i in 0 to ip_proto_c'length-1
  generate
    to_l4_o(i) <= to_l4_req_s(i);
    to_l4_ack_s(i) <= to_l4_i(i);
    from_l4_o(i) <= from_l4_ack_s(i);
    from_l4_req_s(i) <= from_l4_i(i);
  end generate;
 
  receiver: work.ipv4.ipv4_receiver
    generic map(
      header_length_c => header_length_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      unicast_i => unicast_i,
      broadcast_i => broadcast_i,
      
      l2_i => from_l2_i,
      l2_o => from_l2_o,
      
      l4_o => to_l4_s.req,
      l4_i => to_l4_s.ack
      );
  
  to_l4_router: nsl_bnoc.framed.framed_router
    generic map(
      in_count_c => 1,
      out_count_c => ip_proto_l_c'length,
      in_header_count_c => to_l4_in_header_s'length,
      out_header_count_c => to_l4_out_header_s'length
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      in_i(0) => to_l4_s.req,
      in_o(0) => to_l4_s.ack,
      
      out_o => to_l4_req_s,
      out_i => to_l4_ack_s,

      route_header_o => to_l4_in_header_s,
      route_header_i => to_l4_out_header_s,

      route_ready_i => '1',
      route_destination_i => to_l4_destination_s,
      route_drop_i => to_l4_drop_s
      );

  to_l4_route: process(to_l4_in_header_s) is
  begin
    to_l4_drop_s <= '1';
    to_l4_destination_s <= 0;
    to_l4_out_header_s <= to_l4_in_header_s(to_l4_out_header_s'range);

    for i in ip_proto_l_c'range
    loop
      if to_byte(ip_proto_l_c(i)) = to_l4_in_header_s(header_length_c+5) then
        to_l4_drop_s <= '0';
        to_l4_destination_s <= i;
      end if;
    end loop;
  end process;
  
  from_l4_router: nsl_bnoc.framed.framed_router
    generic map(
      in_count_c => ip_proto_l_c'length,
      out_count_c => 1,
      in_header_count_c => from_l4_in_header_s'length,
      out_header_count_c => from_l4_out_header_s'length
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      
      in_i => from_l4_req_s,
      in_o => from_l4_ack_s,

      out_o(0) => from_l4_s.req,
      out_i(0) => from_l4_s.ack,

      route_source_o => from_l4_source_s,

      route_ready_i => '1',
      route_header_o => from_l4_in_header_s,
      route_header_i => from_l4_out_header_s,
      route_destination_i => 0,
      route_drop_i => '0'
      );

  from_l4_route: process(from_l4_in_header_s, from_l4_source_s) is
  begin
    from_l4_out_header_s <= from_l4_in_header_s
                            & to_byte(ip_proto_l_c(from_l4_source_s));
  end process;
  
  transmitter: work.ipv4.ipv4_transmitter
    generic map(
      ttl_c => ttl_c,
      header_length_c => header_length_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      unicast_i => unicast_i,

      l4_i => from_l4_s.req,
      l4_o => from_l4_s.ack,

      l2_o => to_transmit_s.req,
      l2_i => to_transmit_s.ack
      );

  checksummer: work.ipv4.ipv4_checksum_inserter
    generic map(
      header_length_c => header_length_c,
      mtu_c => mtu_c,
      handle_tcp_c => vector_contains(ip_proto_l_c, ip_proto_tcp),
      handle_udp_c => vector_contains(ip_proto_l_c, ip_proto_udp)
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      input_i => to_transmit_s.req,
      input_o => to_transmit_s.ack,

      output_o => to_l2_o,
      output_i => to_l2_i
      );
  
  icmp: work.ipv4.icmpv4
    generic map(
      header_length_c => header_length_c + 5
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      to_l3_o => from_l4_req_s(ip_proto_l_c'length-1),
      to_l3_i => from_l4_ack_s(ip_proto_l_c'length-1),
      from_l3_i => to_l4_req_s(ip_proto_l_c'length-1),
      from_l3_o => to_l4_ack_s(ip_proto_l_c'length-1)
      );

end architecture;
