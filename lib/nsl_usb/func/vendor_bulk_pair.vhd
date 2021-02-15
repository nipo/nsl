library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_usb, nsl_logic, nsl_math, nsl_data, nsl_clocking;
use nsl_usb.usb.all;
use nsl_usb.sie.all;
use nsl_usb.device.all;
use nsl_data.bytestream.all;
use nsl_logic.bool.all;

entity vendor_bulk_pair is
  generic (
    vendor_id_c            : unsigned(15 downto 0);
    product_id_c           : unsigned(15 downto 0);
    device_version_c       : unsigned(15 downto 0);
    manufacturer_c         : string                := "";
    product_c              : string                := "";
    serial_c               : string                := "";
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
    serial_i    : in string := "";

    rx_valid_o     : out std_ulogic;
    rx_data_o      : out byte;
    rx_ready_i     : in  std_ulogic;
    rx_available_o : out unsigned(if_else(hs_supported_c, 9, bulk_fs_mps_l2_c) + bulk_mps_count_l2_c downto 0);

    tx_valid_i  : in  std_ulogic;
    tx_data_i   : in  byte;
    tx_ready_o  : out std_ulogic;
    tx_room_o   : out unsigned(if_else(hs_supported_c, 9, bulk_fs_mps_l2_c) + bulk_mps_count_l2_c downto 0);

    tx_flush_i   : in  std_ulogic := '0';

    transaction_cmd_tap_o : out transaction_cmd;
    transaction_rsp_tap_o : out transaction_rsp;

    phy_data_o   : out nsl_usb.utmi.utmi_data8_sie2phy;
    phy_data_i   : in  nsl_usb.utmi.utmi_data8_phy2sie;
    phy_system_o : out nsl_usb.utmi.utmi_system_sie2phy;
    phy_system_i : in  nsl_usb.utmi.utmi_system_phy2sie
    );
end entity vendor_bulk_pair;

architecture beh of vendor_bulk_pair is

  constant data_ep_no_c  : endpoint_idx_t := 1;

  signal s_out_cmd : transaction_cmd_vector(1 to 1);
  signal s_out_rsp : transaction_rsp_vector(s_out_cmd'range);
  signal s_in_cmd : transaction_cmd_vector(1 to 1);
  signal s_in_rsp : transaction_rsp_vector(s_in_cmd'range);

  signal app_reset_n : std_ulogic;
  
  function if_string(c: string; no: natural)
    return natural is
  begin
    if c'length /= 0 then
      return no;
    else
      return 0;
    end if;
  end function;

  function do_config_descriptor(interval, mps : integer)
    return byte_string
  is
  begin
    return nsl_usb.descriptor.config(
      config_no => 1,
      self_powered => self_powered_c,
      max_power => 150,

      interface0 => nsl_usb.descriptor.interface(
        interface_number => 0,
        alt_setting => 0,
        class => 16#ff#, subclass => 16#ff#, protocol => 16#ff#,
        endpoint0 => nsl_usb.descriptor.endpoint(
          direction => DEVICE_TO_HOST,
          number => data_ep_no_c,
          ttype => "10",
          mps => mps),
        endpoint1 => nsl_usb.descriptor.endpoint(
          direction => HOST_TO_DEVICE,
          number => data_ep_no_c,
          ttype => "10",
          mps => mps)));

  end function;
  
begin

  bus_interface: nsl_usb.device.bus_interface_utmi8
    generic map (
      hs_supported_c => hs_supported_c,
      phy_clock_rate_c => phy_clock_rate_c,

      device_descriptor_c => nsl_usb.descriptor.device(
        hs_support => hs_supported_c,
        mps => 64,
        vendor_id => vendor_id_c,
        product_id => product_id_c,
        device_version => device_version_c,
        manufacturer_str_index => if_string(manufacturer_c, 1),
        product_str_index => if_string(product_c, 2),
        serial_str_index => if_else(serial_i'length /= 0, 10, if_string(serial_c, 3))),

      device_qualifier_c => nsl_usb.descriptor.device_qualifier(
        usb_version => 16#0200#,
        mps0 => 64),

      fs_config_1_c => do_config_descriptor(interval => 255, mps => 2 ** bulk_fs_mps_l2_c),
      hs_config_1_c => do_config_descriptor(interval => 15, mps => 2 ** 9),

      string_1_c => manufacturer_c,
      string_2_c => product_c,
      string_3_c => serial_c,
      
      in_ep_count_c => s_in_cmd'length,
      out_ep_count_c => s_out_cmd'length
      )
    port map(
      reset_n_i => reset_n_i,
      app_reset_n_o => app_reset_n,

      hs_o => hs_o,
      suspend_o => suspend_o,
      online_o => online_o,

      string_10_i => serial_i,

      phy_system_o => phy_system_o,
      phy_system_i => phy_system_i,
      phy_data_o => phy_data_o,
      phy_data_i => phy_data_i,

      transaction_cmd_tap_o => transaction_cmd_tap_o,
      transaction_rsp_tap_o => transaction_rsp_tap_o,

      transaction_out_o => s_out_cmd,
      transaction_out_i => s_out_rsp,
      transaction_in_o => s_in_cmd,
      transaction_in_i => s_in_rsp
      );

  bulk_in : nsl_usb.device.device_ep_bulk_in
    generic map(
      hs_supported_c      => hs_supported_c,
      fs_mps_l2_c => bulk_fs_mps_l2_c,
      mps_count_l2_c => bulk_mps_count_l2_c
      )
    port map(
      clock_i   => phy_system_i.clock,
      reset_n_i => app_reset_n,

      transaction_i => s_in_cmd(data_ep_no_c),
      transaction_o => s_in_rsp(data_ep_no_c),
      
      valid_i => tx_valid_i,
      data_i  => tx_data_i,
      ready_o => tx_ready_o,
      room_o  => tx_room_o,

      flush_i => tx_flush_i
      );

  bulk_out : nsl_usb.device.device_ep_bulk_out
    generic map(
      hs_supported_c      => hs_supported_c,
      fs_mps_l2_c => bulk_fs_mps_l2_c,
      mps_count_l2_c => bulk_mps_count_l2_c
      )
    port map(
      clock_i   => phy_system_i.clock,
      reset_n_i => app_reset_n,

      transaction_i => s_out_cmd(data_ep_no_c),
      transaction_o => s_out_rsp(data_ep_no_c),

      valid_o => rx_valid_o,
      data_o  => rx_data_o,
      ready_i => rx_ready_i,
      available_o => rx_available_o
      );

  app_reset_n_o <= app_reset_n;
  
end architecture;
