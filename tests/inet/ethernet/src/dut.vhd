library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_mii, nsl_data, nsl_inet, nsl_bnoc, nsl_clocking;
use nsl_data.text.all;
use nsl_mii.mii.all;
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

    mode_o : out rgmii_mode_t;
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

begin

  reset_sync_clk: nsl_clocking.async.async_edge
    port map(
      data_i => reset_n_i,
      data_o => reset_n_s,
      clock_i => clock_i
      );

  l1: nsl_mii.rgmii.rgmii_driver
    generic map(
      inband_status_c => false
      )
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_i,

      rgmii_o => phy_o,
      rgmii_i => phy_i,

      mode_o => mode_o,
      link_up_o => link_up_o,
      full_duplex_o => full_duplex_o,

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
