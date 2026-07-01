library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_usb, nsl_memory, nsl_clocking, nsl_hwdep, nsl_bnoc, nsl_spi, nsl_io, nsl_indication;

entity main is
  port (
    usb_dxp_io : inout std_logic;
    usb_dxn_io : inout std_logic;
    usb_rxdp_i : in std_logic;
    usb_rxdn_i : in std_logic;
    usb_pullup_en_o : out std_logic;
    usb_term_dp_io : inout std_logic;
    usb_term_dn_io : inout std_logic;

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
  constant clock_usb_s_hz_c : integer := 60e6;

  signal utmi_s : nsl_usb.utmi.utmi8_bus;

  signal app_reset_n_s, reset_merged_n_s, reset_n_s : std_ulogic;
  signal online_s : std_ulogic;

  signal clock_usb_s, clock_ext_s : std_ulogic;

  type pipe_io is
  record
    cmd, rsp : nsl_bnoc.pipe.pipe_bus_t;
  end record;

  signal loopback_s: pipe_io;

begin

  reset_merged_n_s <= s_n_i(1);

  clock_ext_buffer: nsl_hwdep.clock.clock_buffer
    port map(
      clock_i => clk_i,
      clock_o => clock_ext_s
      );

  pll: nsl_clocking.pll.pll_basic
    generic map(
      input_hz_c => clock_ext_s_hz_c,
      output_hz_c => clock_usb_s_hz_c
      )
    port map(
      clock_i => clock_ext_s,
      reset_n_i => reset_merged_n_s,

      clock_o => clock_usb_s,
      locked_o => reset_n_s
      );
  
  hs_phy: work.softphy.gw_usb2_phy
    port map(
      clock_i => clock_usb_s,
      reset_n_i => reset_n_s,

      usb_dxp_io => usb_dxp_io,
      usb_dxn_io => usb_dxn_io,
      usb_rxdp_i => usb_rxdp_i,
      usb_rxdn_i => usb_rxdn_i,
      usb_pullup_en_o => usb_pullup_en_o,
      usb_term_dp_io => usb_term_dp_io,
      usb_term_dn_io => usb_term_dn_io,

      utmi_i => utmi_s.sie2phy,
      utmi_o => utmi_s.phy2sie
      );

  func: nsl_usb.func.vendor_bulk_pair
    generic map(
      vendor_id_c => x"dead",
      product_id_c => x"beef",
      device_version_c => x"0100",
      manufacturer_c => "Nipo",
      product_c => "NSL Example loopback",
      serial_c => "lol",
      hs_supported_c => true,
      phy_clock_rate_c => clock_usb_s_hz_c,
      self_powered_c => false
      )
    port map(
      phy_system_o => utmi_s.sie2phy.system,
      phy_system_i => utmi_s.phy2sie.system,
      phy_data_o => utmi_s.sie2phy.data,
      phy_data_i => utmi_s.phy2sie.data,

      reset_n_i => reset_n_s,

      app_reset_n_o => app_reset_n_s,
      online_o => online_s,

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
      reset_n_i => app_reset_n_s,
      clock_i(0) => clock_usb_s,

      in_i => loopback_s.cmd.req,
      in_o => loopback_s.cmd.ack,

      out_o => loopback_s.rsp.req,
      out_i => loopback_s.rsp.ack
      );

  ready_led_o <= online_s;
  
  monitor: nsl_indication.activity.activity_blinker
    generic map(
      clock_hz_c => real(clock_ext_s_hz_c)
      )
    port map(
      reset_n_i => reset_merged_n_s,
      clock_i => clock_ext_s,
      activity_i => loopback_s.cmd.req.valid,
      led_o => done_led_o
      );

  mspi_sck_o <= '0';
  mspi_cs_n_o <= 'Z';
  mspi_mosi_io <= 'Z';

end arch;
