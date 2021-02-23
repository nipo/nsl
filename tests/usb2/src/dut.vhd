library ieee;
use ieee.std_logic_1164.all;

library nsl_usb, nsl_memory, nsl_clocking, nsl_hwdep;
use nsl_usb.utmi.all;

entity dut is
  port(
    reset_n_i : in std_logic;

    utmi_data_o : out utmi_data8_sie2phy;
    utmi_data_i : in utmi_data8_phy2sie;
    utmi_system_o : out utmi_system_sie2phy;
    utmi_system_i : in utmi_system_phy2sie;

    flush_i : std_ulogic
    );
end entity;

architecture beh of dut is

  signal tx_valid, tx_ready, rx_valid, rx_ready : std_ulogic;
  signal tx_data, rx_data : std_ulogic_vector(7 downto 0);

  signal reset_n_sys : std_ulogic;
  signal clock_int, reset_n_int : std_ulogic;

  signal online : std_ulogic;

begin

  clk_gen: process
  begin
    while true
    loop
      clock_int <= '0';
      wait for 8333 ps;
      clock_int <= '1';
      wait for 8333 ps;
    end loop;
  end process;

  reset_gen: nsl_clocking.async.async_edge
    port map(
      clock_i => clock_int,
      data_i => reset_n_i,
      data_o => reset_n_int
      );
 
  usb_device: nsl_usb.func.serial_port
    generic map(
      vendor_id_c => x"1234",
      product_id_c => x"5678",
      device_version_c => x"0100",
      manufacturer_c => "NSL",
      product_c => "Some 64-byte long string descr.",
      hs_supported_c => true,
      self_powered_c => false,
      bulk_fs_mps_l2_c => 6,
      bulk_mps_count_l2_c => 1,
      serial_i_length_c => 4
      )
    port map(
      phy_system_o => utmi_system_o,
      phy_system_i => utmi_system_i,
      phy_data_o => utmi_data_o,
      phy_data_i => utmi_data_i,

      reset_n_i => reset_n_int,

      app_reset_n_o => reset_n_sys,

      online_o => online,
      serial_i => "1234",
      
      rx_valid_o => rx_valid,
      rx_data_o => rx_data,
      rx_ready_i => rx_ready,

      tx_valid_i => tx_valid,
      tx_data_i => tx_data,
      tx_ready_o => tx_ready,

      tx_flush_i => flush_i
      );

  loopback: nsl_memory.fifo.fifo_homogeneous
    generic map(
      data_width_c => 8,
      word_count_c => 16,
      clock_count_c => 1
      )
    port map(
      reset_n_i => reset_n_sys,
      clock_i(0) => utmi_system_i.clock,

      out_data_o => tx_data,
      out_ready_i => tx_ready,
      out_valid_o => tx_valid,

      in_data_i => rx_data,
      in_valid_i => rx_valid,
      in_ready_o => rx_ready
      );
  
end architecture;
