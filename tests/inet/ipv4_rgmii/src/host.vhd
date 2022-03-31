library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_inet, nsl_data, nsl_mii;
use nsl_bnoc.committed.all;
use nsl_mii.mii.all;
use nsl_mii.rgmii.all;
use nsl_inet.func.all;
use nsl_inet.ethernet.all;
use nsl_inet.ipv4.all;
use nsl_inet.udp.all;

entity host is
  generic(
    mac_c : mac48_t;
    unicast_c : ipv4_t;
    gateway_c : ipv4_t;
    netmask_c : ipv4_t;
    broadcast_c : ipv4_t;
    udp_port_c: udp_port_t;
    clock_hz_c : natural
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    rgmii_o : out rgmii_io_group_t;
    rgmii_i : in  rgmii_io_group_t;

    udp_tx_i : in committed_req;
    udp_tx_o : out committed_ack;
    udp_rx_o : out committed_req;
    udp_rx_i : in committed_ack;
    
    mode_i : in rgmii_mode_t
    );
end entity;

architecture arch of host is

  constant udp_port_list_c: udp_port_vector(0 to 0) := (0 => udp_port_c);

  type committed_io is
  record
    rx, tx: nsl_bnoc.committed.committed_bus;
  end record;

  signal eth_s: committed_io;
  
begin

  rgmii: nsl_mii.rgmii.rgmii_driver
    port map(
      reset_n_i => reset_n_i,
      clock_i => clock_i,

      rgmii_o => rgmii_o,
      rgmii_i => rgmii_i,
      mode_i => mode_i,

      tx_i => eth_s.tx.req,
      tx_o => eth_s.tx.ack,
      rx_o => eth_s.rx.req,
      rx_i => eth_s.rx.ack
      );
  
  eth_host: nsl_inet.func.ethernet_host
    generic map(
      clock_hz_c => clock_hz_c,
      udp_port_c => (0 => udp_port_c)
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      hwaddr_i => mac_c,
      unicast_i => unicast_c,
      gateway_i => gateway_c,
      netmask_i => netmask_c,
      broadcast_i => broadcast_c,

      l1_tx_o => eth_s.tx.req,
      l1_tx_i => eth_s.tx.ack,
      l1_rx_i => eth_s.rx.req,
      l1_rx_o => eth_s.rx.ack,

      udp_rx_o(0) => udp_rx_o,
      udp_rx_i(0) => udp_rx_i,
      udp_tx_i(0) => udp_tx_i,
      udp_tx_o(0) => udp_tx_o
      );

end;
