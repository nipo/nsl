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

  signal udp_loopback_in_s, udp_loopback_out_s: nsl_bnoc.committed.committed_bus;

  constant local_mac_c : mac48_t := from_hex("02deadbeef01");
  constant local_ipv4_c : ipv4_t := to_ipv4(10,0,0,239);
  constant netmask_ipv4_c : ipv4_t := to_ipv4(255,255,255,0);
  constant broadcast_ipv4_c : ipv4_t := to_ipv4(10,0,0,255);
  constant gateway_ipv4_c : ipv4_t := to_ipv4(10,0,0,254);
  
begin
  
  eth: nsl_inet.func.ethernet_host
    generic map(
      clock_hz_c => clock_hz_c,
      udp_port_c => (0 => 1234)
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i => clock_i,

      unicast_i => local_ipv4_c,
      netmask_i => netmask_ipv4_c,
      gateway_i => gateway_ipv4_c,
      hwaddr_i => local_mac_c,

      l1_tx_o => net_to_l1_o,
      l1_tx_i => net_to_l1_i,
      l1_rx_i => net_from_l1_i,
      l1_rx_o => net_from_l1_o,

      udp_rx_o(0) => udp_loopback_in_s.req,
      udp_rx_i(0) => udp_loopback_in_s.ack,
      udp_tx_i(0) => udp_loopback_out_s.req,
      udp_tx_o(0) => udp_loopback_out_s.ack
      );

  fifo: nsl_bnoc.committed.committed_fifo
    generic map(
      clock_count_c => 1,
      depth_c => 2048
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i(0) => clock_i,

      in_i => udp_loopback_in_s.req,
      in_o => udp_loopback_in_s.ack,
      out_o => udp_loopback_out_s.req,
      out_i => udp_loopback_out_s.ack
      );
  
  led_o(0 to 2) <= button_i(0 to 2);

  blinker: nsl_indication.activity.activity_blinker
    generic map(
      clock_hz_c => real(clock_hz_c)
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i => clock_i,
      activity_i => udp_loopback_in_s.req.valid,
      led_o => led_o(3)
      );

end;
