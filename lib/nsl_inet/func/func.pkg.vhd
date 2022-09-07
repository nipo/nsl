library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, work;
use nsl_bnoc.committed.all;
use work.ethernet.all;
use work.ipv4.all;
use work.udp.all;

package func is
  component ethernet_host is
    generic(
      clock_hz_c : natural;

      -- Whether to implement DHCP
      dhcp_c: boolean := false;

      -- List of additional IP sublayers
      -- ICMP is forbidden here, UDP is forbidden if either an UDP
      -- service is requested or DHCP is enabled.
      ip_proto_c: ip_proto_vector := ip_proto_vector_null_c;

      -- List of additional UDP service ports.
      -- BOOTP ports are forbidden in this list if DHCP is enabled
      -- If DHCP is disabled and this list kept empty,
      -- UDP layer is removed completely.
      udp_port_c: udp_port_vector := udp_port_vector_null_c
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      hwaddr_i: in mac48_t;

      -- Ignored if DHCP enabled
      unicast_i: in ipv4_t := to_ipv4(10,1,1,1);
      gateway_i: in ipv4_t := to_ipv4(10,1,1,254);
      netmask_i: in ipv4_t := to_ipv4(255,255,255,0);
      broadcast_i: in ipv4_t := to_ipv4(10,1,1,255);

      -- Ingored if no DHCP enabled
      dhcp_enable_i: in std_ulogic := '1';
      dhcp_force_renew_i: in std_ulogic := '0';
      dhcp_ready_o: out std_ulogic;

      -- Link to L1 (MII, RGMII, etc.)
      l1_rx_i : in committed_req;
      l1_rx_o : out committed_ack;
      l1_tx_o : out committed_req;
      l1_tx_i : in committed_ack;

      -- UDP services
      udp_tx_i : in committed_req_vector(0 to udp_port_c'length-1) := (others => committed_req_idle_c);
      udp_tx_o : out committed_ack_vector(0 to udp_port_c'length-1);
      udp_rx_o : out committed_req_vector(0 to udp_port_c'length-1);
      udp_rx_i : in committed_ack_vector(0 to udp_port_c'length-1) := (others => committed_ack_blackhole_c);

      -- Other IP services
      ip_tx_i : in committed_req_vector(0 to ip_proto_c'length-1) := (others => committed_req_idle_c);
      ip_tx_o : out committed_ack_vector(0 to ip_proto_c'length-1);
      ip_rx_o : out committed_req_vector(0 to ip_proto_c'length-1);
      ip_rx_i : in committed_ack_vector(0 to ip_proto_c'length-1) := (others => committed_ack_blackhole_c)
      );
  end component;
end package func;
