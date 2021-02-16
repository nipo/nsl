library ieee;
use ieee.std_logic_1164.all;

library nsl_usb, nsl_memory, nsl_clocking, nsl_hwdep;
use nsl_usb.utmi.all;

entity dut is
  generic(
    clock_rate_mhz : integer := 60
    );
  port(
    reset_n_i : in std_logic;
    d_p_io : inout std_logic;
    d_n_io : inout std_logic
  );
end entity;

architecture beh of dut is
  
  signal utmi_data_to_phy : utmi_data8_sie2phy;
  signal utmi_data_from_phy : utmi_data8_phy2sie;
  signal utmi_system_to_phy : utmi_system_sie2phy;
  signal utmi_system_from_phy : utmi_system_phy2sie;

  signal tx_valid, tx_ready, rx_valid, rx_ready : std_ulogic;
  signal tx_data, rx_data : std_ulogic_vector(7 downto 0);

  signal reset_n_sys : std_ulogic;
  signal clock_int, reset_n_int : std_ulogic;

  signal online : std_ulogic;

  signal bus_tx : nsl_usb.io.usb_io_c; 
  signal bus_rx : nsl_usb.io.usb_io_s;

begin

  clk_gen: process
  begin
    while true
    loop
      clock_int <= '0';
      if clock_rate_mhz = 60 then
        wait for 8333 ps;
      elsif clock_rate_mhz = 48 then
        wait for 10416 ps;
      end if;
      clock_int <= '1';
      if clock_rate_mhz = 60 then
        wait for 8333 ps;
      elsif clock_rate_mhz = 48 then
        wait for 10416 ps;
      end if;
    end loop;
  end process;

  reset_gen: nsl_clocking.async.async_edge
    port map(
      clock_i => clock_int,
      data_i => reset_n_i,
      data_o => reset_n_int
      );

  bus_driver: nsl_usb.io.io_fs_driver
    generic map(
      dp_pullup_active_c => 'H'
      )
    port map(
      bus_i => bus_tx,
      bus_o => bus_rx,
      bus_io.dp => d_p_io,
      bus_io.dm => d_n_io,
      dp_pullup_control_io => d_p_io
      );
  
  utmi_fs_phy: nsl_usb.fs_phy.fs_utmi8_phy
    generic map(
      ref_clock_mhz_c => clock_rate_mhz
      )
    port map(
      ref_clock_i => clock_int,
      reset_n_i => reset_n_int,

      bus_i => bus_rx,
      bus_o => bus_tx,

      utmi_data_i => utmi_data_to_phy,
      utmi_data_o => utmi_data_from_phy,
      utmi_system_i => utmi_system_to_phy,
      utmi_system_o => utmi_system_from_phy
      );
  
  usb_device: nsl_usb.func.serial_port
    generic map(
      vendor_id_c => x"dead",
      product_id_c => x"dead",
      device_version_c => x"0100",
      manufacturer_c => "NSL",
      product_c => "FS test device",
      serial_c => "1234",
      hs_supported_c => false,
      self_powered_c => false,
      phy_clock_rate_c => clock_rate_mhz * 1000000
      )
    port map(
      phy_system_o => utmi_system_to_phy,
      phy_system_i => utmi_system_from_phy,
      phy_data_o => utmi_data_to_phy,
      phy_data_i => utmi_data_from_phy,

      reset_n_i => reset_n_int,

      app_reset_n_o => reset_n_sys,

      online_o => online,
      
      rx_valid_o => rx_valid,
      rx_data_o => rx_data,
      rx_ready_i => rx_ready,

      tx_valid_i => tx_valid,
      tx_data_i => tx_data,
      tx_ready_o => tx_ready,

      tx_flush_i => '1'
      );

  loopback: nsl_memory.fifo.fifo_homogeneous
    generic map(
      data_width_c => 8,
      word_count_c => 1024,
      clock_count_c => 1
      )
    port map(
      reset_n_i => reset_n_sys,
      clock_i(0) => utmi_system_from_phy.clock,

      out_data_o => tx_data,
      out_ready_i => tx_ready,
      out_valid_o => tx_valid,

      in_data_i => rx_data,
      in_valid_i => rx_valid,
      in_ready_o => rx_ready
      );
  
end architecture;
