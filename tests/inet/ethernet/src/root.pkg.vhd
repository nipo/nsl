library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_mii, nsl_inet, nsl_bnoc, nsl_data;
use nsl_data.bytestream.all;
use nsl_bnoc.committed.all;
use nsl_mii.link.all;
use nsl_mii.mii.all;
use nsl_mii.rgmii.all;
use nsl_inet.ethernet.all;

package root is

  component dut is
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

      l3_dead_rx_o : out committed_req;
      l3_dead_rx_i : in committed_ack;
      l3_dead_tx_i : in committed_req;
      l3_dead_tx_o : out committed_ack
      );    
  end component;

end package;
