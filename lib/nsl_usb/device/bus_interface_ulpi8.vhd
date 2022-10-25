library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_usb, nsl_data;
use nsl_usb.device.all;
use nsl_usb.usb.all;
use nsl_usb.sie.all;
use nsl_usb.utmi.all;
use nsl_data.bytestream.all;

entity bus_interface_ulpi8 is
  generic (
    hs_supported_c      : boolean     := false;
    self_powered_c      : boolean     := false;
    device_descriptor_c : byte_string;
    device_qualifier_c  : byte_string := null_byte_string;
    fs_config_1_c       : byte_string;
    hs_config_1_c       : byte_string := null_byte_string;
    string_1_c          : string      := "";
    string_2_c          : string      := "";
    string_3_c          : string      := "";
    string_4_c          : string      := "";
    string_5_c          : string      := "";
    string_6_c          : string      := "";
    string_7_c          : string      := "";
    string_8_c          : string      := "";
    string_9_c          : string      := "";

    phy_clock_rate_c : integer := 60000000;
    in_ep_count_c  : endpoint_idx_t := 0;
    out_ep_count_c : endpoint_idx_t := 0;
    string_10_i_length_c : natural := 0
    );
  port (
    reset_n_i     : in  std_ulogic;
    app_reset_n_o : out std_ulogic;
    hs_o          : out std_ulogic;
    suspend_o     : out std_ulogic;
    online_o      : out std_ulogic;

    phy_o : out nsl_usb.ulpi.ulpi8_link2phy;
    phy_i : in  nsl_usb.ulpi.ulpi8_phy2link;

    string_10_i : in string(1 to string_10_i_length_c) := (others => nul);

    transaction_cmd_tap_o : out transaction_cmd;
    transaction_rsp_tap_o : out transaction_rsp;

    frame_number_o : out frame_no_t;
    frame_o        : out std_ulogic;
    microframe_o   : out std_ulogic;

    transaction_out_o : out transaction_cmd_vector(1 to out_ep_count_c);
    transaction_out_i : in  transaction_rsp_vector(1 to out_ep_count_c);
    transaction_in_o : out transaction_cmd_vector(1 to in_ep_count_c);
    transaction_in_i : in  transaction_rsp_vector(1 to in_ep_count_c)
    );
end entity;

architecture beg of bus_interface_ulpi8 is

  signal utmi_data_to_phy : utmi_data8_sie2phy;
  signal utmi_data_from_phy : utmi_data8_phy2sie;
  signal utmi_system_to_phy : utmi_system_sie2phy;
  signal utmi_system_from_phy : utmi_system_phy2sie;

begin

  utmi_converter: nsl_usb.ulpi.utmi8_ulpi8_converter
    port map(
      reset_n_i => reset_n_i,

      ulpi_i => phy_i,
      ulpi_o => phy_o,

      utmi_data_i => utmi_data_to_phy,
      utmi_data_o => utmi_data_from_phy,
      utmi_system_i => utmi_system_to_phy,
      utmi_system_o => utmi_system_from_phy
      );

  bus_interface: nsl_usb.device.bus_interface_utmi8
    generic map (
      hs_supported_c => hs_supported_c,
      self_powered_c => self_powered_c,
      phy_clock_rate_c => phy_clock_rate_c,
      device_descriptor_c => device_descriptor_c,
      device_qualifier_c => device_qualifier_c,
      fs_config_1_c => fs_config_1_c,
      hs_config_1_c => hs_config_1_c,
      string_1_c => string_1_c,
      string_2_c => string_2_c,
      string_3_c => string_3_c,
      string_4_c => string_4_c,
      string_5_c => string_5_c,
      string_6_c => string_6_c,
      string_7_c => string_7_c,
      string_8_c => string_8_c,
      string_9_c => string_9_c,
      
      in_ep_count_c => in_ep_count_c,
      out_ep_count_c => out_ep_count_c,

      string_10_i_length_c => string_10_i_length_c
      )
    port map(
      reset_n_i => reset_n_i,
      app_reset_n_o => app_reset_n_o,
      hs_o => hs_o,
      suspend_o => suspend_o,
      online_o => online_o,

      phy_system_o => utmi_system_to_phy,
      phy_system_i => utmi_system_from_phy,
      phy_data_o => utmi_data_to_phy,
      phy_data_i => utmi_data_from_phy,

      string_10_i => string_10_i,
      
      frame_number_o => frame_number_o,
      frame_o => frame_o,
      microframe_o => microframe_o,

      transaction_cmd_tap_o => transaction_cmd_tap_o,
      transaction_rsp_tap_o => transaction_rsp_tap_o,
      
      transaction_out_o => transaction_out_o,
      transaction_out_i => transaction_out_i,
      transaction_in_o => transaction_in_o,
      transaction_in_i => transaction_in_i
      );

end architecture;
