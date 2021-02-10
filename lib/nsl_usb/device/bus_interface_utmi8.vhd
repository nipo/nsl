library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_usb, nsl_data, nsl_logic, nsl_clocking;
use nsl_usb.device.all;
use nsl_usb.usb.all;
use nsl_data.bytestream.all;
use nsl_logic.bool.all;
use nsl_usb.sie.all;

entity bus_interface_utmi8 is
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
    out_ep_count_c : endpoint_idx_t := 0
    );
  port (
    reset_n_i     : in  std_ulogic;
    app_reset_n_o : out std_ulogic;
    hs_o          : out std_ulogic;
    suspend_o     : out std_ulogic;
    online_o      : out std_ulogic;

    phy_system_o : out nsl_usb.utmi.utmi_system_sie2phy;
    phy_system_i : in  nsl_usb.utmi.utmi_system_phy2sie;
    phy_data_o   : out nsl_usb.utmi.utmi_data8_sie2phy;
    phy_data_i   : in  nsl_usb.utmi.utmi_data8_phy2sie;

    string_10_i : in string := "";
    
    transfer_cmd_tap_o : out transfer_cmd;
    transfer_rsp_tap_o : out transfer_rsp;

    transfer_out_o : out transfer_cmd_vector(1 to out_ep_count_c);
    transfer_out_i : in  transfer_rsp_vector(1 to out_ep_count_c);
    transfer_in_o : out transfer_cmd_vector(1 to in_ep_count_c);
    transfer_in_i : in  transfer_rsp_vector(1 to in_ep_count_c)
    );
end entity;

architecture beg of bus_interface_utmi8 is

  signal s_hs, s_suspend, s_app_reset_n, s_chirp_tx : std_ulogic;

  signal s_packet_out    : packet_out;
  signal s_packet_in_cmd : packet_in_cmd;
  signal s_packet_in_rsp : packet_in_rsp;

  signal s_ep_no        : nsl_usb.usb.endpoint_idx_t;

  signal s_dev_addr       : device_address_t;

  signal s_transfer_cmd, s_transfer_ep0_cmd : transfer_cmd;
  signal s_transfer_rsp, s_transfer_ep0_rsp : transfer_rsp;

  signal s_desc_cmd : nsl_usb.sie.descriptor_cmd;
  signal s_desc_rsp : nsl_usb.sie.descriptor_rsp;

  signal s_halted_in, s_halt_in, s_clear_in : std_ulogic_vector(1 to in_ep_count_c);
  signal s_halted_out, s_halt_out, s_clear_out : std_ulogic_vector(1 to out_ep_count_c);

  signal reset_n : std_ulogic;

begin

  hs_o <= s_hs;
  suspend_o <= s_suspend;
  app_reset_n_o <= s_app_reset_n;

  tap: process(phy_system_i.clock)
  begin
    if rising_edge(phy_system_i.clock) then
      transfer_cmd_tap_o <= s_transfer_cmd;
      transfer_rsp_tap_o <= s_transfer_rsp;
    end if;
  end process;

  reset_sync: nsl_clocking.async.async_edge
    port map(
      clock_i => phy_system_i.clock,
      data_i => reset_n_i,
      data_o => reset_n
      );

  management : nsl_usb.sie.sie_management
    generic map (
      hs_supported_c => hs_supported_c,
      phy_clock_rate_c => phy_clock_rate_c
      )
    port map (
      reset_n_i     => reset_n,
      app_reset_n_o => s_app_reset_n,
      hs_o          => s_hs,
      suspend_o     => s_suspend,
      chirp_tx_o    => s_chirp_tx,
      phy_system_i  => phy_system_i,
      phy_system_o  => phy_system_o
      );

  packet_engine: nsl_usb.sie.sie_packet
    port map (
      clock_i     => phy_system_i.clock,
      reset_n_i   => s_app_reset_n,

      phy_data_o  => phy_data_o,
      phy_data_i  => phy_data_i,

      chirp_tx_i  => s_chirp_tx,

      out_o => s_packet_out,
      in_o => s_packet_in_rsp,
      in_i => s_packet_in_cmd
      );

  transfer_engine: nsl_usb.sie.sie_transfer
    generic map (
      hs_supported_c => hs_supported_c,
      phy_clock_rate_c => phy_clock_rate_c
      )
    port map (
      clock_i       => phy_system_i.clock,
      reset_n_i     => s_app_reset_n,

      hs_i        => s_hs,
      dev_addr_i  => s_dev_addr,

      packet_out_i => s_packet_out,
      packet_in_i => s_packet_in_rsp,
      packet_in_o => s_packet_in_cmd,

      transfer_o => s_transfer_cmd,
      transfer_i => s_transfer_rsp
      );

  router: nsl_usb.sie.sie_transfer_router
    generic map(
      in_ep_count_c => in_ep_count_c,
      out_ep_count_c => out_ep_count_c
      )
    port map(
      clock_i       => phy_system_i.clock,
      reset_n_i     => s_app_reset_n,

      transfer_i => s_transfer_cmd,
      transfer_o => s_transfer_rsp,

      transfer_ep0_o => s_transfer_ep0_cmd,
      transfer_ep0_i => s_transfer_ep0_rsp,

      halted_in_o => s_halted_in,
      halt_in_i => s_halt_in,
      clear_in_i => s_clear_in,

      halted_out_o => s_halted_out,
      halt_out_i => s_halt_out,
      clear_out_i => s_clear_out,

      transfer_in_o => transfer_in_o,
      transfer_in_i => transfer_in_i,

      transfer_out_o => transfer_out_o,
      transfer_out_i => transfer_out_i
      );
  
  ep0: nsl_usb.sie.sie_ep0
    generic map (
      in_ep_count_c => in_ep_count_c,
      out_ep_count_c => out_ep_count_c,
      self_powered_c => self_powered_c
      )
    port map (
      clock_i       => phy_system_i.clock,
      reset_n_i     => s_app_reset_n,

      dev_addr_o       => s_dev_addr,
      configured_o     => online_o,

      transfer_i => s_transfer_ep0_cmd,
      transfer_o => s_transfer_ep0_rsp,

      halted_in_i => s_halted_in,
      halt_in_o => s_halt_in,
      clear_in_o => s_clear_in,

      halted_out_i => s_halted_out,
      halt_out_o => s_halt_out,
      clear_out_o => s_clear_out,

      descriptor_o       => s_desc_cmd,
      descriptor_i       => s_desc_rsp
      );

  descriptor : nsl_usb.sie.sie_descriptor
    generic map(
      hs_supported_c    => hs_supported_c,
      device_descriptor => device_descriptor_c,
      device_qualifier  => device_qualifier_c,
      fs_config_1       => fs_config_1_c,
      hs_config_1       => hs_config_1_c,
      string_1          => string_1_c,
      string_2          => string_2_c,
      string_3          => string_3_c,
      string_4          => string_4_c,
      string_5          => string_5_c,
      string_6          => string_6_c,
      string_7          => string_7_c,
      string_8          => string_8_c,
      string_9          => string_9_c
      )
    port map(
      clock_i => phy_system_i.clock,
      reset_n_i => s_app_reset_n,

      string_10_i => string_10_i,

      cmd_i => s_desc_cmd,
      rsp_o => s_desc_rsp
      );

end architecture;
