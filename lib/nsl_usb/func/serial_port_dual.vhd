library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_usb, nsl_logic, nsl_math, nsl_data, nsl_clocking, nsl_bnoc;
use nsl_usb.usb.all;
use nsl_usb.sie.all;
use nsl_usb.device.all;
use nsl_usb.descriptor.all;
use nsl_data.bytestream.all;
use nsl_logic.bool.all;

entity serial_port_dual is
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

    rx0_o     : out nsl_bnoc.pipe.pipe_req_t;
    rx0_i     : in  nsl_bnoc.pipe.pipe_ack_t;
    rx0_available_o : out unsigned(if_else(hs_supported_c, 9, bulk_fs_mps_l2_c) + bulk_mps_count_l2_c downto 0);

    tx0_i  : in  nsl_bnoc.pipe.pipe_req_t;
    tx0_o  : out nsl_bnoc.pipe.pipe_ack_t;
    tx0_room_o   : out unsigned(if_else(hs_supported_c, 9, bulk_fs_mps_l2_c) + bulk_mps_count_l2_c downto 0);
    tx0_flush_i   : in  std_ulogic := '0';

    rx1_o     : out nsl_bnoc.pipe.pipe_req_t;
    rx1_i     : in  nsl_bnoc.pipe.pipe_ack_t;
    rx1_available_o : out unsigned(if_else(hs_supported_c, 9, bulk_fs_mps_l2_c) + bulk_mps_count_l2_c downto 0);

    tx1_i  : in  nsl_bnoc.pipe.pipe_req_t;
    tx1_o  : out nsl_bnoc.pipe.pipe_ack_t;
    tx1_room_o   : out unsigned(if_else(hs_supported_c, 9, bulk_fs_mps_l2_c) + bulk_mps_count_l2_c downto 0);
    tx1_flush_i   : in  std_ulogic := '0';

    frame_number_o : out frame_no_t;
    frame_o        : out std_ulogic;

    transaction_cmd_tap_o : out transaction_cmd;
    transaction_rsp_tap_o : out transaction_rsp;

    phy_data_o   : out nsl_usb.utmi.utmi_data8_sie2phy;
    phy_data_i   : in  nsl_usb.utmi.utmi_data8_phy2sie;
    phy_system_o : out nsl_usb.utmi.utmi_system_sie2phy;
    phy_system_i : in  nsl_usb.utmi.utmi_system_phy2sie
    );
end entity serial_port_dual;

architecture beh of serial_port_dual is

  constant data0_ep_no_c  : endpoint_idx_t := 1;
  constant data1_ep_no_c  : endpoint_idx_t := 2;
  constant notif0_ep_no_c : endpoint_idx_t := 3;
  constant notif1_ep_no_c : endpoint_idx_t := 4;

  signal s_out_cmd : transaction_cmd_vector(1 to 2);
  signal s_out_rsp : transaction_rsp_vector(s_out_cmd'range);
  signal s_in_cmd : transaction_cmd_vector(1 to 4);
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
      max_power => 500,

      interface0 => nsl_usb.descriptor.interface(
        interface_number => 0,
        alt_setting => 0,
        class => 2, subclass => 2, protocol => 0,
        functional_desc =>
        nsl_usb.descriptor.cdc_functional_header
        & nsl_usb.descriptor.cdc_functional_acm
        & nsl_usb.descriptor.cdc_functional_union(control => 0, sub0 => 1)
        & nsl_usb.descriptor.cdc_functional_call_management(
          capabilities => 0, data_interface => 1),
        endpoint0 => nsl_usb.descriptor.endpoint(
          direction => DEVICE_TO_HOST,
          number => notif0_ep_no_c,
          ttype => EP_TTYPE_INTERRUPT,
          mps => 8,
          interval => interval)),

      interface1 => nsl_usb.descriptor.interface(
        interface_number => 1, alt_setting => 0,
        class => 10,
        endpoint0 => nsl_usb.descriptor.endpoint(
          direction => DEVICE_TO_HOST,
          number => data0_ep_no_c,
          ttype => EP_TTYPE_BULK,
          mps => mps),
        endpoint1 => nsl_usb.descriptor.endpoint(
          direction => HOST_TO_DEVICE,
          number => data0_ep_no_c,
          ttype => EP_TTYPE_BULK,
          mps => mps)),

      interface2 => nsl_usb.descriptor.interface(
        interface_number => 2,
        alt_setting => 0,
        class => 2, subclass => 2, protocol => 0,
        functional_desc =>
        nsl_usb.descriptor.cdc_functional_header
        & nsl_usb.descriptor.cdc_functional_acm
        & nsl_usb.descriptor.cdc_functional_union(control => 2, sub0 => 3)
        & nsl_usb.descriptor.cdc_functional_call_management(
          capabilities => 0, data_interface => 3),
        endpoint0 => nsl_usb.descriptor.endpoint(
          direction => DEVICE_TO_HOST,
          number => notif1_ep_no_c,
          ttype => EP_TTYPE_INTERRUPT,
          mps => 8,
          interval => interval)),

      interface3 => nsl_usb.descriptor.interface(
        interface_number => 3, alt_setting => 0,
        class => 10,
        endpoint0 => nsl_usb.descriptor.endpoint(
          direction => DEVICE_TO_HOST,
          number => data1_ep_no_c,
          ttype => EP_TTYPE_BULK,
          mps => mps),
        endpoint1 => nsl_usb.descriptor.endpoint(
          direction => HOST_TO_DEVICE,
          number => data1_ep_no_c,
          ttype => EP_TTYPE_BULK,
          mps => mps))

      );

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
      out_ep_count_c => s_out_cmd'length,

      string_10_i_length_c => serial_i_length_c
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

      frame_number_o => frame_number_o,
      frame_o => frame_o,

      transaction_cmd_tap_o => transaction_cmd_tap_o,
      transaction_rsp_tap_o => transaction_rsp_tap_o,

      transaction_out_o => s_out_cmd,
      transaction_out_i => s_out_rsp,
      transaction_in_o => s_in_cmd,
      transaction_in_i => s_in_rsp
      );

  bulk0_in : nsl_usb.device.device_ep_bulk_in
    generic map(
      hs_supported_c      => hs_supported_c,
      fs_mps_l2_c => bulk_fs_mps_l2_c,
      mps_count_l2_c => bulk_mps_count_l2_c
      )
    port map(
      clock_i   => phy_system_i.clock,
      reset_n_i => app_reset_n,

      transaction_i => s_in_cmd(data0_ep_no_c),
      transaction_o => s_in_rsp(data0_ep_no_c),
      
      data_i => tx0_i,
      data_o => tx0_o,
      room_o => tx0_room_o,

      flush_i => tx0_flush_i
      );

  bulk0_out : nsl_usb.device.device_ep_bulk_out
    generic map(
      hs_supported_c      => hs_supported_c,
      fs_mps_l2_c => bulk_fs_mps_l2_c,
      mps_count_l2_c => bulk_mps_count_l2_c
      )
    port map(
      clock_i   => phy_system_i.clock,
      reset_n_i => app_reset_n,

      transaction_i => s_out_cmd(data0_ep_no_c),
      transaction_o => s_out_rsp(data0_ep_no_c),

      data_o => rx0_o,
      data_i => rx0_i,
      available_o => rx0_available_o
      );

  notify0_in : nsl_usb.device.device_ep_in_noop
    port map(
      clock_i   => phy_system_i.clock,
      reset_n_i => app_reset_n,

      transaction_i => s_in_cmd(notif0_ep_no_c),
      transaction_o => s_in_rsp(notif0_ep_no_c)
      );

  bulk1_in : nsl_usb.device.device_ep_bulk_in
    generic map(
      hs_supported_c      => hs_supported_c,
      fs_mps_l2_c => bulk_fs_mps_l2_c,
      mps_count_l2_c => bulk_mps_count_l2_c
      )
    port map(
      clock_i   => phy_system_i.clock,
      reset_n_i => app_reset_n,

      transaction_i => s_in_cmd(data1_ep_no_c),
      transaction_o => s_in_rsp(data1_ep_no_c),
      
      data_i => tx1_i,
      data_o => tx1_o,
      room_o => tx1_room_o,

      flush_i => tx1_flush_i
      );

  bulk1_out : nsl_usb.device.device_ep_bulk_out
    generic map(
      hs_supported_c      => hs_supported_c,
      fs_mps_l2_c => bulk_fs_mps_l2_c,
      mps_count_l2_c => bulk_mps_count_l2_c
      )
    port map(
      clock_i   => phy_system_i.clock,
      reset_n_i => app_reset_n,

      transaction_i => s_out_cmd(data1_ep_no_c),
      transaction_o => s_out_rsp(data1_ep_no_c),

      data_o => rx1_o,
      data_i => rx1_i,
      available_o => rx1_available_o
      );

  notify1_in : nsl_usb.device.device_ep_in_noop
    port map(
      clock_i   => phy_system_i.clock,
      reset_n_i => app_reset_n,

      transaction_i => s_in_cmd(notif1_ep_no_c),
      transaction_o => s_in_rsp(notif1_ep_no_c)
      );

  app_reset_n_o <= app_reset_n;
  
end architecture;
