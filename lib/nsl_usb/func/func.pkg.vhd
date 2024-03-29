library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_usb, nsl_data, nsl_logic, nsl_bnoc;
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
      bulk_mps_count_l2_c : integer := 1;

      serial_i_length_c : natural := 0
      );
    port (
      reset_n_i     : in  std_ulogic;
      app_reset_n_o : out std_ulogic;
      hs_o        : out std_ulogic;
      suspend_o   : out std_ulogic;
      online_o    : out std_ulogic;
      serial_i    : in string(1 to serial_i_length_c) := (others => nul);

      rx_o     : out nsl_bnoc.pipe.pipe_req_t;
      rx_i     : in  nsl_bnoc.pipe.pipe_ack_t;
      rx_available_o : out unsigned(if_else(hs_supported_c, 9, bulk_fs_mps_l2_c) + bulk_mps_count_l2_c downto 0);

      tx_i  : in  nsl_bnoc.pipe.pipe_req_t;
      tx_o  : out nsl_bnoc.pipe.pipe_ack_t;
      tx_room_o   : out unsigned(if_else(hs_supported_c, 9, bulk_fs_mps_l2_c) + bulk_mps_count_l2_c downto 0);

      tx_flush_i   : in  std_ulogic := '0';

      frame_number_o : out frame_no_t;
      frame_o        : out std_ulogic;

      transaction_cmd_tap_o : out nsl_usb.sie.transaction_cmd;
      transaction_rsp_tap_o : out nsl_usb.sie.transaction_rsp;

      phy_data_o   : out nsl_usb.utmi.utmi_data8_sie2phy;
      phy_data_i   : in  nsl_usb.utmi.utmi_data8_phy2sie;
      phy_system_o : out nsl_usb.utmi.utmi_system_sie2phy;
      phy_system_i : in  nsl_usb.utmi.utmi_system_phy2sie
      );
  end component serial_port;

  component vendor_bulk_pair is
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
      bulk_mps_count_l2_c : integer := 1;
      serial_i_length_c : natural := 0
      );
    port (
      reset_n_i     : in  std_ulogic;
      app_reset_n_o : out std_ulogic;
      hs_o        : out std_ulogic;
      suspend_o   : out std_ulogic;
      online_o    : out std_ulogic;
      serial_i    : in string(1 to serial_i_length_c) := (others => nul);

      rx_o     : out nsl_bnoc.pipe.pipe_req_t;
      rx_i     : in  nsl_bnoc.pipe.pipe_ack_t;
      rx_available_o : out unsigned(if_else(hs_supported_c, 9, bulk_fs_mps_l2_c) + bulk_mps_count_l2_c downto 0);

      tx_i  : in  nsl_bnoc.pipe.pipe_req_t;
      tx_o  : out nsl_bnoc.pipe.pipe_ack_t;
      tx_room_o   : out unsigned(if_else(hs_supported_c, 9, bulk_fs_mps_l2_c) + bulk_mps_count_l2_c downto 0);

      tx_flush_i   : in  std_ulogic := '0';

      frame_number_o : out frame_no_t;
      frame_o        : out std_ulogic;
      microframe_o   : out std_ulogic;

      transaction_cmd_tap_o : out nsl_usb.sie.transaction_cmd;
      transaction_rsp_tap_o : out nsl_usb.sie.transaction_rsp;

      phy_data_o   : out nsl_usb.utmi.utmi_data8_sie2phy;
      phy_data_i   : in  nsl_usb.utmi.utmi_data8_phy2sie;
      phy_system_o : out nsl_usb.utmi.utmi_system_sie2phy;
      phy_system_i : in  nsl_usb.utmi.utmi_system_phy2sie
      );
  end component vendor_bulk_pair;

  component vendor_framed_pair is
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
      framed_fs_mps_l2_c : integer range 3 to 6 := 6;
      framed_double_buffer_c : boolean := true;
      serial_i_length_c : natural := 0
      );
    port (
      reset_n_i     : in  std_ulogic;
      app_reset_n_o : out std_ulogic;
      hs_o        : out std_ulogic;
      suspend_o   : out std_ulogic;
      online_o    : out std_ulogic;
      serial_i    : in string(1 to serial_i_length_c) := (others => nul);

      out_o     : out nsl_bnoc.framed.framed_req;
      out_i     : in  nsl_bnoc.framed.framed_ack;
      in_i      : in  nsl_bnoc.framed.framed_req;
      in_o      : out nsl_bnoc.framed.framed_ack;

      frame_number_o : out frame_no_t;
      frame_o        : out std_ulogic;
      microframe_o   : out std_ulogic;

      transaction_cmd_tap_o : out nsl_usb.sie.transaction_cmd;
      transaction_rsp_tap_o : out nsl_usb.sie.transaction_rsp;

      phy_data_o   : out nsl_usb.utmi.utmi_data8_sie2phy;
      phy_data_i   : in  nsl_usb.utmi.utmi_data8_phy2sie;
      phy_system_o : out nsl_usb.utmi.utmi_system_sie2phy;
      phy_system_i : in  nsl_usb.utmi.utmi_system_phy2sie
      );
  end component vendor_framed_pair;

end package;
