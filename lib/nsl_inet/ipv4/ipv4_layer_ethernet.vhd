library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_data, nsl_inet, nsl_math;
use nsl_inet.ethernet.all;
use nsl_bnoc.committed.all;
use nsl_bnoc.framed.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_inet.ipv4.all;

entity ipv4_layer_ethernet is
  generic(
    l1_header_length_c : integer := 0;
    mtu_c : integer := 1500;
    ttl_c : integer := 64;
    ip_proto_c : ip_proto_vector;
    arp_cache_count_c : integer := 8;
    clock_i_hz_c : natural
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    -- Layer-1 header, supposed to be fixed, if any.
    l1_header_i : in byte_string(0 to l1_header_length_c-1) := (others => x"00");

    unicast_i : in ipv4_t;
    netmask_i : in ipv4_t := (others => x"ff");
    gateway_i : in ipv4_t := (others => x"00");
    hwaddr_i : in mac48_t;

    to_l4_o : out committed_req_array(0 to ip_proto_c'length-1);
    to_l4_i : in committed_ack_array(0 to ip_proto_c'length-1);
    from_l4_i : in committed_req_array(0 to ip_proto_c'length-1);
    from_l4_o : out committed_ack_array(0 to ip_proto_c'length-1);

    ip_to_l2_o : out committed_req;
    ip_to_l2_i : in committed_ack;
    ip_from_l2_i : in committed_req;
    ip_from_l2_o : out committed_ack;
    arp_to_l2_o : out committed_req;
    arp_to_l2_i : in committed_ack;
    arp_from_l2_i : in committed_req;
    arp_from_l2_o : out committed_ack
    );
end entity;

architecture beh of ipv4_layer_ethernet is

  constant icmp_singleton : ip_proto_vector(0 to 0) := (others => ip_proto_icmp);
  constant ip_proto_l_c : ip_proto_vector(0 to ip_proto_c'length)
    := ip_proto_c & icmp_singleton;

  signal rx_to_arp_s: framed_bus;
  
  signal to_l4_s, from_l4_s: committed_bus;
  signal to_l4_req_s : framed_req_array(0 to ip_proto_l_c'length-1);
  signal to_l4_ack_s : framed_ack_array(0 to ip_proto_l_c'length-1);
  signal from_l4_req_s : framed_req_array(0 to ip_proto_l_c'length-1);
  signal from_l4_ack_s : framed_ack_array(0 to ip_proto_l_c'length-1);

  type framed_io is
  record
    cmd, rsp: framed_bus;
  end record;

  signal arp_req_s: framed_io;

  signal notify_s : byte_string(0 to l1_header_length_c+6+1+4);
  signal notify_valid_s : std_ulogic;

  signal to_l4_drop_s: std_ulogic;
  signal to_l4_in_header_s : byte_string(0 to 0);
  signal to_l4_destination_s : natural range 0 to ip_proto_l_c'length-1;
  signal from_l4_out_header_s : byte_string(0 to 0);
  signal from_l4_source_s : natural range 0 to ip_proto_l_c'length-1;

  signal broadcast_s : ipv4_t;
  
begin

  broadcast_s <= unicast_i or (not netmask_i);
  
  l4_map: for i in 0 to ip_proto_c'length-1
  generate
    to_l4_o(i) <= to_l4_req_s(i);
    to_l4_ack_s(i) <= to_l4_i(i);
    from_l4_o(i) <= from_l4_ack_s(i);
    from_l4_req_s(i) <= from_l4_i(i);
  end generate;
 
  receiver: nsl_inet.ipv4.ipv4_receiver
    generic map(
      l12_header_length_c => 7+l1_header_length_c,
      mtu_c => mtu_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      unicast_i => unicast_i,
      broadcast_i => broadcast_s,

      notify_o => notify_s,
      notify_valid_o => notify_valid_s,
      
      l2_i => ip_from_l2_i,
      l2_o => ip_from_l2_o,
      
      l4_o => to_l4_s.req,
      l4_i => to_l4_s.ack
      );
  
  to_l4_router: nsl_bnoc.framed.framed_router
    generic map(
      in_count_c => 1,
      out_count_c => ip_proto_l_c'length,
      in_header_count_c => 1,
      out_header_count_c => 0
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      in_i(0) => to_l4_s.req,
      in_o(0) => to_l4_s.ack,
      
      out_o => to_l4_req_s,
      out_i => to_l4_ack_s,

      route_header_o => to_l4_in_header_s,

      route_ready_i => '1',
      route_destination_i => to_l4_destination_s,
      route_drop_i => to_l4_drop_s
      );

  to_l4_route: process(to_l4_in_header_s) is
  begin
    to_l4_drop_s <= '1';
    to_l4_destination_s <= 0;

    for i in ip_proto_l_c'range
    loop
      if to_byte(ip_proto_l_c(i)) = to_l4_in_header_s(0) then
        to_l4_drop_s <= '0';
        to_l4_destination_s <= i;
      end if;
    end loop;
  end process;
  
  from_l4_router: nsl_bnoc.framed.framed_router
    generic map(
      in_count_c => ip_proto_l_c'length,
      out_count_c => 1,
      in_header_count_c => 0,
      out_header_count_c => 1
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
      route_header_i => from_l4_out_header_s,
      route_destination_i => 0,
      route_drop_i => '0'
      );

  from_l4_route: process(from_l4_source_s) is
  begin
    from_l4_out_header_s(0) <= to_byte(ip_proto_l_c(from_l4_source_s));
  end process;
  
  transmitter: nsl_inet.ipv4.ipv4_transmitter
    generic map(
      ttl_c => ttl_c,
      mtu_c => mtu_c,
      l12_header_length_c => 7+l1_header_length_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      unicast_i => unicast_i,

      l4_i => from_l4_s.req,
      l4_o => from_l4_s.ack,

      l2_o => ip_to_l2_o,
      l2_i => ip_to_l2_i,

      l12_query_o => arp_req_s.cmd.req,
      l12_query_i => arp_req_s.cmd.ack,
      l12_reply_i => arp_req_s.rsp.req,
      l12_reply_o => arp_req_s.rsp.ack
      );

  arp: nsl_inet.ipv4.arp_ethernet
    generic map(
      l1_header_length_c => l1_header_length_c,
      cache_count_c => arp_cache_count_c,
      clock_i_hz_c => clock_i_hz_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      unicast_i => unicast_i,
      netmask_i => netmask_i,
      gateway_i => gateway_i,
      hwaddr_i => hwaddr_i,

      l1_header_i => l1_header_i,

      notify_i => notify_s,
      notify_valid_i => notify_valid_s,
      
      to_l2_o => arp_to_l2_o,
      to_l2_i => arp_to_l2_i,
      from_l2_i => arp_from_l2_i,
      from_l2_o => arp_from_l2_o,

      query_i => arp_req_s.cmd.req,
      query_o => arp_req_s.cmd.ack,
      reply_o => arp_req_s.rsp.req,
      reply_i => arp_req_s.rsp.ack
      );

  icmp: nsl_inet.ipv4.icmpv4
    generic map(
      header_length_c => ipv4_header_length_c
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
