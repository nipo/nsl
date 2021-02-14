library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_usb, nsl_data, nsl_logic;
use nsl_usb.utmi.all;
use nsl_usb.device.all;
use nsl_usb.usb.all;
use nsl_data.bytestream.byte;
use nsl_logic.bool.if_else;

package func is

  constant null_string : string := "";
  
  component serial_port is
    generic (
      vendor_id_c            : unsigned(15 downto 0);
      product_id_c           : unsigned(15 downto 0);
      device_version_c       : unsigned(15 downto 0);
      manufacturer_c         : string                := null_string;
      product_c              : string                := null_string;
      serial_c               : string                := null_string;
      hs_supported_c         : boolean               := false;
      self_powered_c         : boolean               := false;
      phy_clock_rate_c : integer := 60000000;
      bulk_fs_mps_l2_c : integer range 3 to 6 := 6;
      bulk_mps_count_l2_c : integer := 1
      );
    port (
      reset_n_i     : in  std_ulogic;
      app_reset_n_o : out std_ulogic;
      hs_o        : out std_ulogic;
      suspend_o   : out std_ulogic;
      online_o    : out std_ulogic;
      serial_i    : in string := null_string;

      rx_valid_o     : out std_ulogic;
      rx_data_o      : out byte;
      rx_ready_i     : in  std_ulogic;
      rx_available_o : out unsigned(if_else(hs_supported_c, 9, bulk_fs_mps_l2_c) + bulk_mps_count_l2_c downto 0);

      tx_valid_i  : in  std_ulogic;
      tx_data_i   : in  byte;
      tx_ready_o  : out std_ulogic;
      tx_room_o   : out unsigned(if_else(hs_supported_c, 9, bulk_fs_mps_l2_c) + bulk_mps_count_l2_c downto 0);

      tx_flush_i   : in  std_ulogic := '0';

      transfer_cmd_tap_o : out nsl_usb.sie.transfer_cmd;
      transfer_rsp_tap_o : out nsl_usb.sie.transfer_rsp;

      phy_data_o   : out nsl_usb.utmi.utmi_data8_sie2phy;
      phy_data_i   : in  nsl_usb.utmi.utmi_data8_phy2sie;
      phy_system_o : out nsl_usb.utmi.utmi_system_sie2phy;
      phy_system_i : in  nsl_usb.utmi.utmi_system_phy2sie
      );
  end component serial_port;

end package;
