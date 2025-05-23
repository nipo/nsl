library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_mii, nsl_data, nsl_inet, nsl_bnoc, nsl_clocking;
use nsl_data.text.all;
use nsl_mii.link.all;
use nsl_mii.mii.all;
use nsl_mii.flit.all;
use nsl_mii.rgmii.all;
use nsl_data.bytestream.all;
use nsl_data.crc.all;
use nsl_mii.testing.all;
use nsl_inet.ethernet.all;

entity dut is
  generic(
    hwaddr_c : mac48_t := from_hex("020000000001")
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    phy_i : in rgmii_io_group_t;
    phy_o : out rgmii_io_group_t;

    speed_o : out link_speed_t;
    link_up_o : out std_ulogic;
    full_duplex_o : out std_ulogic;

    l3_dead_rx_o : out nsl_bnoc.committed.committed_req;
    l3_dead_rx_i : in nsl_bnoc.committed.committed_ack;
    l3_dead_tx_i : in nsl_bnoc.committed.committed_req;
    l3_dead_tx_o : out nsl_bnoc.committed.committed_ack
    );    
end dut;

architecture beh of dut is

  signal reset_n_s : std_ulogic;

  constant ethertype_list_c : ethertype_vector(0 to 0) := (0 => 16#dead#);
  
  signal l1_l2_s, l2_l1_s : nsl_bnoc.committed.committed_bus;

  signal ibs_s : link_status_t;
  signal rx_clock_s: std_ulogic;
  signal rx_flit_s: mii_flit_t;
  
begin

  ibs: nsl_mii.link_monitor.link_monitor_inband_status
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      rx_clock_i => rx_clock_s,
      rx_flit_i => rx_flit_s,
      link_status_o => ibs_s
      );

  speed_o <= ibs_s.speed;
  link_up_o <= '1' when ibs_s.up else '0';
  full_duplex_o <= '1' when ibs_s.duplex = LINK_DUPLEX_FULL else '0';
  
  reset_sync_clk: nsl_clocking.async.async_edge
    port map(
      data_i => reset_n_i,
      data_o => reset_n_s,
      clock_i => clock_i
      );

  l1: nsl_mii.rgmii.rgmii_driver
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_i,

      mode_i => ibs_s.speed,
      rgmii_o => phy_o,
      rgmii_i => phy_i,

      rx_clock_o => rx_clock_s,
      rx_flit_o => rx_flit_s,

      rx_o => l1_l2_s.req,
      rx_i => l1_l2_s.ack,

      tx_i => l2_l1_s.req,
      tx_o => l2_l1_s.ack
      );
  
  eth: nsl_inet.ethernet.ethernet_layer
    generic map(
      ethertype_c => ethertype_list_c,
      l1_header_length_c => 0
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_s,

      local_address_i => hwaddr_c,

      to_l3_o(0) => l3_dead_rx_o,
      to_l3_i(0) => l3_dead_rx_i,
      from_l3_i(0) => l3_dead_tx_i,
      from_l3_o(0) => l3_dead_tx_o,

      to_l1_o => l2_l1_s.req,
      to_l1_i => l2_l1_s.ack,
      from_l1_i => l1_l2_s.req,
      from_l1_o => l1_l2_s.ack
      );

end architecture;
