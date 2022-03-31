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

package helper is
  component host is
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
  end component;
end package helper;
