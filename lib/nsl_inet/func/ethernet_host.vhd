library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_inet;
use nsl_bnoc.committed.all;
use nsl_inet.ethernet.all;
use nsl_inet.ipv4.all;
use nsl_inet.udp.all;

entity ethernet_host is
  generic(
    clock_hz_c : natural;

    dhcp_c: boolean := false;

    ip_proto_c: ip_proto_vector := ip_proto_vector_null_c;

    udp_port_c: udp_port_vector := udp_port_vector_null_c
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    hwaddr_i: in mac48_t;

    unicast_i: in ipv4_t := to_ipv4(10,1,1,1);
    gateway_i: in ipv4_t := to_ipv4(10,1,1,254);
    netmask_i: in ipv4_t := to_ipv4(255,255,255,0);
    broadcast_i: in ipv4_t := to_ipv4(10,1,1,255);

    dhcp_enable_i: in std_ulogic := '1';
    dhcp_force_renew_i: in std_ulogic := '0';
    dhcp_ready_o: out std_ulogic;

    l1_rx_i : in committed_req;
    l1_rx_o : out committed_ack;
    l1_tx_o : out committed_req;
    l1_tx_i : in committed_ack;

    udp_tx_i : in committed_req_vector(0 to udp_port_c'length-1) := (others => committed_req_idle_c);
    udp_tx_o : out committed_ack_vector(0 to udp_port_c'length-1);
    udp_rx_o : out committed_req_vector(0 to udp_port_c'length-1);
    udp_rx_i : in committed_ack_vector(0 to udp_port_c'length-1) := (others => committed_ack_blackhole_c);

    ip_tx_i : in committed_req_vector(0 to ip_proto_c'length-1) := (others => committed_req_idle_c);
    ip_tx_o : out committed_ack_vector(0 to ip_proto_c'length-1);
    ip_rx_o : out committed_req_vector(0 to ip_proto_c'length-1);
    ip_rx_i : in committed_ack_vector(0 to ip_proto_c'length-1) := (others => committed_ack_blackhole_c)
    );
end entity;

architecture beh of ethernet_host is

  function ip_proto_vector_gen(base: ip_proto_vector;
                               add_udp: boolean) return ip_proto_vector
  is
    constant udp_singleton: ip_proto_vector(0 to 0) := (0 => ip_proto_udp);
    constant wo_udp: ip_proto_vector(0 to base'length-1) := base;
    constant w_udp: ip_proto_vector(0 to base'length) := wo_udp & udp_singleton;
  begin
    if add_udp then
      return w_udp;
    else
      return wo_udp;
    end if;
  end function;
  
  function udp_port_vector_gen(base: udp_port_vector;
                               add_dhcp: boolean) return udp_port_vector
  is
    constant dhcp_singleton: udp_port_vector(0 to 1) := (0 => 67, 1 => 68);
    constant wo_dhcp: udp_port_vector(0 to base'length-1) := udp_port_c;
    constant w_dhcp: udp_port_vector(0 to base'length+1) := wo_dhcp & dhcp_singleton;
  begin
    if add_dhcp then
      return w_dhcp;
    else
      return wo_dhcp;
    end if;
  end function;
  
  constant ethertype_list_c : ethertype_vector(0 to 1) := (ethertype_ipv4, ethertype_arp);
  constant udp_port_l_c : udp_port_vector := udp_port_vector_gen(udp_port_c, dhcp_c);
  constant has_udp: boolean := udp_port_l_c'length /= 0;
  constant ip_proto_l_c : ip_proto_vector := ip_proto_vector_gen(ip_proto_c, has_udp);
  constant udp_index_c : natural := ip_proto_c'length;

  type committed_trx is
  record
    rx, tx: committed_bus;
  end record;

  signal ipv4_s, arp_s, udp_s: committed_trx;
  signal ip_rx_req_s, ip_tx_req_s : committed_req_array(0 to ip_proto_l_c'length-1);
  signal ip_rx_ack_s, ip_tx_ack_s : committed_ack_array(0 to ip_proto_l_c'length-1);

begin
  
  ip_map: for i in 0 to ip_proto_c'length-1
  generate
    ip_rx_o(i) <= ip_rx_req_s(i);
    ip_rx_ack_s(i) <= ip_rx_i(i);
    ip_tx_o(i) <= ip_tx_ack_s(i);
    ip_tx_req_s(i) <= ip_tx_i(i);
  end generate;
  
  eth: nsl_inet.ethernet.ethernet_layer
    generic map(
      ethertype_c => ethertype_list_c,
      l1_header_length_c => 0
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      local_address_i => hwaddr_i,

      to_l3_o(0) => ipv4_s.rx.req,
      to_l3_o(1) => arp_s.rx.req,
      to_l3_i(0) => ipv4_s.rx.ack,
      to_l3_i(1) => arp_s.rx.ack,
      from_l3_i(0) => ipv4_s.tx.req,
      from_l3_i(1) => arp_s.tx.req,
      from_l3_o(0) => ipv4_s.tx.ack,
      from_l3_o(1) => arp_s.tx.ack,

      to_l1_o => l1_tx_o,
      to_l1_i => l1_tx_i,
      from_l1_i => l1_rx_i,
      from_l1_o => l1_rx_o
      );

  ipv4: nsl_inet.ipv4.ipv4_layer_ethernet
    generic map(
      l1_header_length_c => 0,
      ip_proto_c => ip_proto_l_c,
      clock_i_hz_c => clock_hz_c
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i => clock_i,

      unicast_i => unicast_i,
      netmask_i => netmask_i,
      gateway_i => gateway_i,
      hwaddr_i => hwaddr_i,

      to_l4_o => ip_rx_req_s,
      to_l4_i => ip_rx_ack_s,
      from_l4_i => ip_tx_req_s,
      from_l4_o => ip_tx_ack_s,

      ip_to_l2_o => ipv4_s.tx.req,
      ip_to_l2_i => ipv4_s.tx.ack,
      ip_from_l2_i => ipv4_s.rx.req,
      ip_from_l2_o => ipv4_s.rx.ack,
      arp_to_l2_o => arp_s.tx.req,
      arp_to_l2_i => arp_s.tx.ack,
      arp_from_l2_i => arp_s.rx.req,
      arp_from_l2_o => arp_s.rx.ack
      );

  if_udp: if has_udp
  generate
    constant dhcp_index_c : natural := udp_port_c'length;
    signal udp_rx_req_s, udp_tx_req_s : committed_req_array(0 to udp_port_l_c'length-1);
    signal udp_rx_ack_s, udp_tx_ack_s : committed_ack_array(0 to udp_port_l_c'length-1);
  begin
    udp_map: for i in 0 to udp_port_c'length-1
    generate
      udp_rx_o(i) <= udp_rx_req_s(i);
      udp_rx_ack_s(i) <= udp_rx_i(i);
      udp_tx_o(i) <= udp_tx_ack_s(i);
      udp_tx_req_s(i) <= udp_tx_i(i);
    end generate;
    
    udp: nsl_inet.udp.udp_layer
      generic map(
        tx_mtu_c => 1500,
        udp_port_c => udp_port_l_c,
        header_length_c => ipv4_header_length_c
        )
      port map(
        reset_n_i => reset_n_i,
        clock_i => clock_i,

        from_l3_i => ip_rx_req_s(udp_index_c),
        from_l3_o => ip_rx_ack_s(udp_index_c),
        to_l3_o => ip_tx_req_s(udp_index_c),
        to_l3_i => ip_tx_ack_s(udp_index_c),

        to_l5_o => udp_rx_req_s,
        to_l5_i => udp_rx_ack_s,
        from_l5_i => udp_tx_req_s,
        from_l5_o => udp_tx_ack_s
        );

    if_dhcp: if dhcp_c
    generate
--      dhcp: nsl_inet.dhcp.dhcp_client
--        port map(
--          reset_n_i => reset_n_i,
--          clock_i => clock_i,
--
--          from_l3_i => ip_rx_req_s(udp_index_c),
--          from_l3_o => ip_rx_ack_s(udp_index_c),
--          to_l3_o => ip_tx_req_s(udp_index_c),
--          to_l3_i => ip_tx_ack_s(udp_index_c),
--
--          to_l5_o(0) => udp_rx_o,
--          to_l5_i(0) => udp_rx_i,
--          from_l5_i(0) => udp_tx_i,
--          from_l5_o(0) => udp_tx_o
--          );
    end generate;
  end generate;

end architecture;
