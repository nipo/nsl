library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_inet, nsl_data, nsl_uart, nsl_smi, nsl_indication,
  nsl_math;
use nsl_inet.ethernet.all;
use nsl_inet.ipv4.all;
use nsl_inet.udp.all;
use nsl_data.bytestream.all;

entity func_main is
  generic(
    clock_hz_c : integer
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    net_to_l1_o : out nsl_bnoc.committed.committed_req;
    net_to_l1_i : in nsl_bnoc.committed.committed_ack;
    net_from_l1_i : in nsl_bnoc.committed.committed_req;
    net_from_l1_o : out nsl_bnoc.committed.committed_ack;
    net_smi_o : out nsl_smi.smi.smi_master_o;
    net_smi_i : in nsl_smi.smi.smi_master_i;

    button_i : in std_ulogic_vector(0 to 3);
    led_o : out std_ulogic_vector(0 to 3);

    uart_o : out std_ulogic;
    uart_i : in std_ulogic
    );
end func_main;

architecture arch of func_main is

  constant ethertype_list_c : ethertype_vector(0 to 1) := (0 => ethertype_ipv4,
                                                           1 => ethertype_arp);
  constant ip_proto_list_c: ip_proto_vector(0 to 0) := (0 => ip_proto_udp);
  
  signal l2_to_ipv4_s, ipv4_to_l2_s, l2_to_arp_s, arp_to_l2_s,
    l3_to_udp_s, udp_to_l3_s, udp_loopback_s: nsl_bnoc.committed.committed_bus;
  signal s_frame_tx, s_frame_rx: nsl_bnoc.framed.framed_bus;

  signal reset_n : std_ulogic;

  constant local_mac_c : mac48_t := from_hex("02deadbeef01");
  constant local_ipv4_c : ipv4_t := to_ipv4(10,0,5,1);
  constant netmask_ipv4_c : ipv4_t := to_ipv4(255,255,255,0);
  constant broadcast_ipv4_c : ipv4_t := to_ipv4(10,0,5,255);
  constant gateway_ipv4_c : ipv4_t := to_ipv4(10,0,5,254);
  
begin
  
  eth: nsl_inet.ethernet.ethernet_layer
    generic map(
      ethertype_c => ethertype_list_c,
      l1_header_length_c => 0
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      local_address_i => local_mac_c,

      to_l1_o => net_to_l1_o,
      to_l1_i => net_to_l1_i,
      from_l1_i => net_from_l1_i,
      from_l1_o => net_from_l1_o,

      to_l3_o(0) => l2_to_ipv4_s.req,
      to_l3_o(1) => l2_to_arp_s.req,
      to_l3_i(0) => l2_to_ipv4_s.ack,
      to_l3_i(1) => l2_to_arp_s.ack,
      from_l3_i(0) => ipv4_to_l2_s.req,
      from_l3_i(1) => arp_to_l2_s.req,
      from_l3_o(0) => ipv4_to_l2_s.ack,
      from_l3_o(1) => arp_to_l2_s.ack
      );

  ipv4: nsl_inet.ipv4.ipv4_layer_ethernet
    generic map(
      l1_header_length_c => 0,
      ip_proto_c => ip_proto_list_c,
      clock_i_hz_c => clock_hz_c
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i => clock_i,

      unicast_i => local_ipv4_c,
      netmask_i => netmask_ipv4_c,
      gateway_i => gateway_ipv4_c,
      hwaddr_i => local_mac_c,

      to_l4_o(0) => l3_to_udp_s.req,
      to_l4_i(0) => l3_to_udp_s.ack,
      from_l4_i(0) => udp_to_l3_s.req,
      from_l4_o(0) => udp_to_l3_s.ack,

      ip_to_l2_o => ipv4_to_l2_s.req,
      ip_to_l2_i => ipv4_to_l2_s.ack,
      ip_from_l2_i => l2_to_ipv4_s.req,
      ip_from_l2_o => l2_to_ipv4_s.ack,

      arp_to_l2_o => arp_to_l2_s.req,
      arp_to_l2_i => arp_to_l2_s.ack,
      arp_from_l2_i => l2_to_arp_s.req,
      arp_from_l2_o => l2_to_arp_s.ack
      );

  udp: nsl_inet.udp.udp_layer
    generic map(
      tx_mtu_c => 1500,
      udp_port_c => (0 => 1234),
      header_length_c => ipv4_header_length_c
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i => clock_i,

      from_L3_i => l3_to_udp_s.req,
      from_L3_o => l3_to_udp_s.ack,
      to_L3_o => udp_to_l3_s.req,
      to_L3_i => udp_to_l3_s.ack,

      to_l5_o(0) => udp_loopback_s.req,
      to_l5_i(0) => udp_loopback_s.ack,
      from_l5_i(0) => udp_loopback_s.req,
      from_l5_o(0) => udp_loopback_s.ack
      );
  
  led_o(0 to 2) <= button_i(0 to 2);

  blinker: nsl_indication.activity.activity_blinker
    generic map(
      clock_hz_c => real(clock_hz_c)
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i => clock_i,
      activity_i => udp_loopback_s.req.valid,
      led_o => led_o(3)
      );

end;
