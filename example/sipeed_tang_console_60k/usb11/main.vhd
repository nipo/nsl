library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_usb, nsl_memory, nsl_clocking, nsl_hwdep, nsl_bnoc, nsl_spi, nsl_io, nsl_indication;

entity main is
  port (
    usb_dp_io, usb_dn_io, usb_dp_pull_io : inout std_logic;
    usb_unused_io : inout std_logic_vector(0 to 5);
    s_n_i: in std_ulogic_vector(1 to 2);
    done_led_o: inout std_logic;
    ready_led_o: inout std_logic;
    clk_i: in std_ulogic;

    mspi_sck_o : out std_ulogic;
    mspi_cs_n_o, mspi_mosi_io: inout std_logic;
    mspi_miso_i : in std_ulogic
  );
end main;

architecture arch of main is

  constant clock_ext_s_hz_c : integer := 50e6;
  constant clock_usb_s_hz_c : integer := 48e6;

  signal usb_o : nsl_usb.io.usb_io_c;
  signal usb_i : nsl_usb.io.usb_io_s;
  signal tx_valid, tx_ready, rx_valid, rx_ready : std_ulogic;
  signal tx_data, rx_data : std_ulogic_vector(7 downto 0);

  signal utmi_data_to_phy : nsl_usb.utmi.utmi_data8_sie2phy;
  signal utmi_data_from_phy : nsl_usb.utmi.utmi_data8_phy2sie;
  signal utmi_system_to_phy : nsl_usb.utmi.utmi_system_sie2phy;
  signal utmi_system_from_phy : nsl_usb.utmi.utmi_system_phy2sie;

  signal app_reset_n, reset_merged_n, reset_n : std_ulogic;
  signal online : std_ulogic;

  signal clock_usb_s, clock_ext_s : std_ulogic;

  type pipe_io is
  record
    cmd, rsp : nsl_bnoc.pipe.pipe_bus_t;
  end record;

  signal loopback_s: pipe_io;

begin

  usb_unused_io <= (others => 'Z');
  
  reset_merged_n <= s_n_i(1);

  clock_ext_buffer: nsl_hwdep.clock.clock_buffer
    port map(
      clock_i => clk_i,
      clock_o => clock_ext_s
      );

  pll: nsl_clocking.pll.pll_basic
    generic map(
      input_hz_c => clock_ext_s_hz_c,
      output_hz_c => clock_usb_s_hz_c,
      hw_variant_c => "ice40(out=global,in=core)"
      )
    port map(
      clock_i => clock_ext_s,
      reset_n_i => reset_merged_n,

      clock_o => clock_usb_s,
      locked_o => reset_n
      );

  io_driver: nsl_usb.io.io_fs_driver
    port map(
      bus_o => usb_i,
      bus_i => usb_o,
      bus_io.dp => usb_dp_io,
      bus_io.dm => usb_dn_io,
      dp_pullup_control_io => usb_dp_pull_io
      );
  
  fs_phy: nsl_usb.fs_phy.fs_utmi8_phy
    generic map(
      ref_clock_mhz_c => clock_usb_s_hz_c / 1000000
      )
    port map(
      ref_clock_i => clock_usb_s,
      reset_n_i => reset_n,

      bus_o => usb_o,
      bus_i => usb_i,

      utmi_data_i => utmi_data_to_phy,
      utmi_data_o => utmi_data_from_phy,
      utmi_system_i => utmi_system_to_phy,
      utmi_system_o => utmi_system_from_phy
      );

  func: nsl_usb.func.vendor_bulk_pair
    generic map(
      vendor_id_c => x"dead",
      product_id_c => x"beef",
      device_version_c => x"0100",
      manufacturer_c => "Nipo",
      product_c => "NSL Example loopback",
      serial_c => "lol",
      hs_supported_c => false,
      phy_clock_rate_c => clock_usb_s_hz_c,
      self_powered_c => false
      )
    port map(
      phy_system_o => utmi_system_to_phy,
      phy_system_i => utmi_system_from_phy,
      phy_data_o => utmi_data_to_phy,
      phy_data_i => utmi_data_from_phy,

      reset_n_i => reset_n,

      app_reset_n_o => app_reset_n,
      online_o => online,

      rx_o => loopback_s.cmd.req,
      rx_i => loopback_s.cmd.ack,

      tx_i => loopback_s.rsp.req,
      tx_o => loopback_s.rsp.ack
      );

  loopback_fifo: nsl_bnoc.pipe.pipe_fifo
    generic map(
      word_count_c => 4096,
      clock_count_c => 1
      )
    port map(
      reset_n_i => app_reset_n,
      clock_i(0) => clock_usb_s,

      in_i => loopback_s.cmd.req,
      in_o => loopback_s.cmd.ack,

      out_o => loopback_s.rsp.req,
      out_i => loopback_s.rsp.ack
      );

  ready_led_o <= online;
  
  monitor: nsl_indication.activity.activity_blinker
    generic map(
      clock_hz_c => real(clock_ext_s_hz_c)
      )
    port map(
      reset_n_i => reset_merged_n,
      clock_i => clock_ext_s,
      activity_i => loopback_s.cmd.req.valid,
      led_o => done_led_o
      );

  mspi_sck_o <= '0';
  mspi_cs_n_o <= 'Z';
  mspi_mosi_io <= 'Z';

end arch;
