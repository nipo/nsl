library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_usb, nsl_memory, nsl_clocking, nsl_hwdep;

entity main is
  port (
      phy_clk: in std_ulogic;
      phy_data: inout std_logic_vector(7 downto 0);
      phy_dir: in std_ulogic;
      phy_nxt: in std_ulogic;
      phy_stp: out std_ulogic;
      phy_reset: out std_ulogic;

      btn: in std_ulogic;
      led: out std_logic
  );
end main;

architecture arch of main is

  signal tx_valid, tx_ready, rx_valid, rx_ready : std_ulogic;
  signal tx_data, rx_data : std_ulogic_vector(7 downto 0);

  signal ulpi : nsl_usb.ulpi.ulpi8;
  signal utmi_data_to_phy : nsl_usb.utmi.utmi_data8_sie2phy;
  signal utmi_data_from_phy : nsl_usb.utmi.utmi_data8_phy2sie;
  signal utmi_system_to_phy : nsl_usb.utmi.utmi_system_sie2phy;
  signal utmi_system_from_phy : nsl_usb.utmi.utmi_system_phy2sie;
  
  signal reset_n_sys, reset_merged_n, reset_n : std_ulogic;
  signal clock_int, reset_n_int : std_ulogic;

  signal online : std_ulogic;

  function nibble_to_char(nibble : unsigned(3 downto 0))
    return character
  is
  begin
    if nibble < 10 then
      return character'val(character'pos('0') + to_integer(nibble));
    else
      return character'val(character'pos('a') + to_integer(nibble) - 10);
    end if;
  end function;
  
  signal s_device_serial : string(1 to 8);
  signal s_device_uid : unsigned(31 downto 0);

begin

  clock_gen: nsl_hwdep.clock.clock_internal
    port map(
      clock_o => clock_int
      );

  reset_gen: nsl_hwdep.reset.reset_at_startup
    port map(
      clock_i => clock_int,
      reset_n_o => reset_n_int
      );

  reset_merged_n <= reset_n_int and btn;
  
  reset_sync: nsl_clocking.async.async_edge
    port map(
      clock_i => clock_int,
      data_i => reset_merged_n,
      data_o => reset_n
      );

  ulpi_driver: nsl_usb.ulpi.ulpi8_line_driver
    port map(
      clock_i => phy_clk,
      reset_o => phy_reset,
      data_io => phy_data,
      dir_i => phy_dir,
      nxt_i => phy_nxt,
      stp_o => phy_stp,
      
      bus_o => ulpi.phy2link,
      bus_i => ulpi.link2phy
      );

  utmi_converter: nsl_usb.ulpi.utmi8_ulpi8_converter
    port map(
      ulpi_i => ulpi.phy2link,
      ulpi_o => ulpi.link2phy,
      
      utmi_data_i => utmi_data_to_phy,
      utmi_data_o => utmi_data_from_phy,
      utmi_system_i => utmi_system_to_phy,
      utmi_system_o => utmi_system_from_phy
      );
  
  func: nsl_usb.func.serial_port
    generic map(
      vendor_id_c => x"dead",
      product_id_c => x"dead",
      device_version_c => x"0100",
      manufacturer_c => "NSL",
      product_c => "Serial loopback demo",
      hs_supported_c => true,
      bulk_mps_count_l2_c => 2,
      self_powered_c => false
      )
    port map(
      phy_system_o => utmi_system_to_phy,
      phy_system_i => utmi_system_from_phy,
      phy_data_o => utmi_data_to_phy,
      phy_data_i => utmi_data_from_phy,

      reset_n_i => reset_n,
      
      app_reset_n_o => reset_n_sys,

      serial_i => s_device_serial,

      online_o => online,
      
      rx_valid_o => rx_valid,
      rx_data_o => rx_data,
      rx_ready_i => rx_ready,

      tx_valid_i => tx_valid,
      tx_data_i => tx_data,
      tx_ready_o => tx_ready
      );

  uid: nsl_hwdep.uid.uid32_reader
    port map(
      clock_i => ulpi.phy2link.clock,
      reset_n_i => reset_n,
      uid_o => s_device_uid
      );

  uid_to_string: process(s_device_uid)
  begin
    for i in 0 to 7
    loop
      s_device_serial(i+1) <= nibble_to_char(s_device_uid(31-i*4 downto 28-i*4));
    end loop;
  end process;

  loopback: nsl_memory.fifo.fifo_homogeneous
    generic map(
      data_width_c => 8,
      word_count_c => 1024,
      clock_count_c => 1
      )
    port map(
      reset_n_i => reset_n_sys,
      clock_i(0) => ulpi.phy2link.clock,

      out_data_o => tx_data,
      out_ready_i => tx_ready,
      out_valid_o => tx_valid,

      in_data_i => rx_data,
      in_valid_i => rx_valid,
      in_ready_o => rx_ready
      );

  led <= online;

end arch;
