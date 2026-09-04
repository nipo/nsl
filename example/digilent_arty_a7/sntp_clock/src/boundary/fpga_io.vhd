library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_mii, nsl_clocking, nsl_smi, nsl_digilent, nsl_dvi,
  nsl_indication, nsl_color, nsl_io, gatecap_generated, work, nsl_hwdep;
use nsl_amba.axi4_stream.all;
use nsl_mii.flit.all;
use nsl_color.rgb.all;

entity fpga_io is
  port(
    clock_100_i: in std_ulogic;

    eth_col_i : in std_ulogic;
    eth_crs_i : in std_ulogic;
    eth_mdc_o : out std_ulogic;
    eth_mdio_io : inout std_logic;
    eth_ref_clk_o : out std_ulogic;
    eth_reset_n_o : inout std_logic;
    eth_rx_clk_i : in std_ulogic;
    eth_rx_dv_i : in std_ulogic;
    eth_rxd_i : in std_ulogic_vector(3 downto 0);
    eth_rxerr_i : in std_ulogic;
    eth_tx_clk_i : in std_ulogic;
    eth_tx_en_o : out std_ulogic;
    eth_txd_o : out std_ulogic_vector(3 downto 0);

    ja_io: inout nsl_digilent.pmod.pmod_double_t;

    btn_i: in std_ulogic_vector(0 to 3);
    ld_o: out std_ulogic_vector(4 to 7)
    );
end entity;

architecture beh of fpga_io is

  constant clock_hz_c : natural := 100000000;

  constant color_palette_c : rgb24_vector(0 to 7) := (
    rgb24_black,
    rgb24_red,
    rgb24_lime,
    rgb24_blue,
    rgb24_yellow,
    rgb24_cyan,
    rgb24_magenta,
    rgb24_white);

  signal clock_25_s, clock_100_s, reset_n_25_s, reset_n_s : std_ulogic;
  signal ext_reset_n_s, eth_tx_er_s : std_ulogic;
  signal eth_smi_s : nsl_smi.smi.smi_master_i;
  signal eth_smi_c : nsl_smi.smi.smi_master_o;

  signal mii_rx_s, rx_clean_s, tx_s, tx_prefilled_s : bus_t;
  signal rx_error_s : std_ulogic;

  signal led_s : std_ulogic_vector(0 to 3);
  signal seconds_s, address_s, ntp_server_s : unsigned(31 downto 0);
  signal link_up_s, dhcp_valid_s, sntp_valid_s : std_ulogic;

  signal eth_txd_s : std_ulogic_vector(3 downto 0);
  signal eth_tx_en_s : std_ulogic;
  signal rx_clock_s, rx_reset_n_s, tx_clock_s, tx_reset_n_s, int_reset_n_s, user_reset_s : std_ulogic;

  signal sof_s, sol_s, pixel_ready_s, pixel_valid_s : std_ulogic;
  signal pixel_s : rgb24;
  signal term_row_s : unsigned(2 downto 0);
  signal term_column_s : unsigned(3 downto 0);
  signal term_write_s : std_ulogic;
  signal term_character_s : unsigned(7 downto 0);
  signal term_foreground_s : unsigned(2 downto 0);

begin

  buf: nsl_clocking.distribution.clock_buffer
    port map(
      clock_i => clock_100_i,
      clock_o => clock_100_s
      );

  clk25: nsl_clocking.pll.pll_basic
    generic map(
      input_hz_c => 100e6,
      output_hz_c => 25e6,
      hw_variant_c => "series67(type=pll)"
      )
    port map(
      clock_i => clock_100_s,
      clock_o => clock_25_s,
      reset_n_i => reset_n_s,
      locked_o => reset_n_25_s
      );

  phy_ref_clock: nsl_io.clock.clock_output_se_to_se
    port map(
      clock_i => clock_25_s,
      port_o => eth_ref_clk_o
      );

  int_reset_gen: nsl_hwdep.reset.reset_at_startup
    port map(
      clock_i => clock_100_s,
      reset_n_o => int_reset_n_s
      );

  ext_reset_n_s <= int_reset_n_s and not btn_i(0) and not user_reset_s;
  reset_sync: nsl_clocking.async.async_edge
    port map(
      clock_i => clock_100_s,
      data_i => ext_reset_n_s,
      data_o => reset_n_s
      );

  eth_reset_n_o <= '0' when reset_n_25_s = '0' else 'Z';

  main_inst: work.func.func_main
    generic map(
      clock_hz_c => clock_hz_c
      )
    port map(
      clock_i => clock_100_s,
      reset_n_i => reset_n_s,

      l1_rx_i => rx_clean_s.m,
      l1_rx_o => rx_clean_s.s,
      l1_tx_o => tx_s.m,
      l1_tx_i => tx_s.s,

      smi_o => eth_smi_c,
      smi_i => eth_smi_s,

      led_o => led_s,

      link_up_o => link_up_s,
      dhcp_valid_o => dhcp_valid_s,
      sntp_valid_o => sntp_valid_s,
      address_o => address_s,
      ntp_server_o => ntp_server_s,

      seconds_o => seconds_s
      );

  ld_o(4 to 7) <= led_s(0 to 3);

  mii: nsl_mii.mii.mii_axi_driver_resync
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_100_s,

      rx_clock_o => rx_clock_s,
      tx_clock_o => tx_clock_s,

      mii_i.rx.clk => eth_rx_clk_i,
      mii_i.rx.d => eth_rxd_i,
      mii_i.rx.dv => eth_rx_dv_i,
      mii_i.rx.er => eth_rxerr_i,
      mii_i.tx.clk => eth_tx_clk_i,
      mii_i.status.crs => eth_crs_i,
      mii_i.status.col => eth_col_i,
      mii_o.tx.d => eth_txd_s,
      mii_o.tx.en => eth_tx_en_s,
      mii_o.tx.er => eth_tx_er_s,

      rx_o => mii_rx_s.m,
      rx_i => mii_rx_s.s,

      tx_i => tx_prefilled_s.m,
      tx_o => tx_prefilled_s.s
      );

  -- Errored frames (user bit) are dropped before entering the stack;
  -- the store-and-forward fifo also absorbs the line-to-core rate
  -- difference.
  rx_error_s <= user(axi4_flit_cfg, mii_rx_s.m)(0);

  rx_cleaner: nsl_amba.stream_fifo.axi4_stream_fifo_clean
    generic map(
      config_c => axi4_flit_cfg,
      fifo_word_count_l2 => 11
      )
    port map(
      clock_i => clock_100_s,
      reset_n_i => reset_n_s,

      in_error_i => rx_error_s,
      in_i => mii_rx_s.m,
      in_o => mii_rx_s.s,

      out_o => rx_clean_s.m,
      out_i => rx_clean_s.s
      );

  -- The MII line has no flow control: beats must be available at
  -- line rate for a whole frame once transmission starts.
  tx_prefill: nsl_amba.axi4_stream.axi4_stream_prefill_buffer
    generic map(
      config_c => axi4_flit_cfg,
      prefill_count_c => 64
      )
    port map(
      clock_i => clock_100_s,
      reset_n_i => reset_n_s,

      in_i => tx_s.m,
      in_o => tx_s.s,

      out_o => tx_prefilled_s.m,
      out_i => tx_prefilled_s.s
      );

  eth_txd_o <= eth_txd_s;
  eth_tx_en_o <= eth_tx_en_s;

  rx_reset_sync: nsl_clocking.async.async_edge
    port map(
      clock_i => rx_clock_s,
      data_i => reset_n_s,
      data_o => rx_reset_n_s
      );

  tx_reset_sync: nsl_clocking.async.async_edge
    port map(
      clock_i => tx_clock_s,
      data_i => reset_n_s,
      data_o => tx_reset_n_s
      );

  -- Gatecap rack over the chip TAP: raw MII wires in their own clock
  -- domains, stack status on the core clock.
  observer: gatecap_generated.observer.observer_core
    generic map(
      burst_length_l2_c => 6
      )
    port map(
      clock_i => clock_100_s,
      reset_n_i => int_reset_n_s,

      mii_rx_rx_rx_clock_i => rx_clock_s,
      mii_rx_rx_reset_n_i => rx_reset_n_s,
      mii_rx_rx_d_i => eth_rxd_i,
      mii_rx_rx_dv_i => eth_rx_dv_i,
      mii_rx_rx_er_i => eth_rxerr_i,

      mii_tx_tx_tx_clock_i => tx_clock_s,
      mii_tx_tx_reset_n_i => tx_reset_n_s,
      mii_tx_tx_d_i => eth_txd_s,
      mii_tx_tx_en_i => eth_tx_en_s,

      panel_mac_clock_i => clock_100_s,
      panel_reset_n_i => int_reset_n_s,
      panel_link_up_i => link_up_s,
      panel_dhcp_lease_i => dhcp_valid_s,
      panel_sntp_valid_i => sntp_valid_s,
      panel_address_i => address_s,
      panel_ntp_server_i => ntp_server_s,
      panel_ntp_date_i => seconds_s,
      panel_reset_o => user_reset_s
      );

  mdio_driver: nsl_smi.smi.smi_master_line_driver
    port map(
      mdc_o => eth_mdc_o,
      mdio_io => eth_mdio_io,
      master_o => eth_smi_s,
      master_i => eth_smi_c
      );

  display: nsl_digilent.pmod_oled_rgb.pmod_oled_rgb_driver
    generic map(
      clock_i_hz_c => clock_hz_c
      )
    port map(
      clock_i => clock_100_s,
      reset_n_i => reset_n_s,

      sof_o => sof_s,
      sol_o => sol_s,
      pixel_ready_o => pixel_ready_s,
      pixel_valid_i => pixel_valid_s,
      pixel_i => pixel_s,

      pmod_io => ja_io
      );

  terminal: nsl_dvi.terminal.terminal_text_buffer
    generic map(
      row_count_l2_c => 3,
      column_count_l2_c => 4,
      character_count_l2_c => 8,
      color_palette_c => color_palette_c,
      font_c => nsl_indication.font_6x8.font_6x8_c,
      underline_support_c => false,
      font_hscale_c => 1,
      font_vscale_c => 1
      )
    port map(
      video_clock_i => clock_100_s,
      video_reset_n_i => reset_n_s,

      sof_i => sof_s,
      sol_i => sol_s,
      pixel_ready_i => pixel_ready_s,
      pixel_valid_o => pixel_valid_s,
      pixel_o => pixel_s,

      term_clock_i => clock_100_s,
      term_reset_n_i => reset_n_s,

      row_i => term_row_s,
      column_i => term_column_s,
      enable_i => term_write_s,
      write_i => term_write_s,
      character_i => term_character_s,
      foreground_i => term_foreground_s,
      background_i => "000"
      );

  screen: work.func.screen_text
    port map(
      clock_i => clock_100_s,
      reset_n_i => reset_n_s,

      link_up_i => link_up_s,
      dhcp_valid_i => dhcp_valid_s,
      sntp_valid_i => sntp_valid_s,
      address_i => address_s,
      ntp_server_i => ntp_server_s,
      seconds_i => seconds_s,

      row_o => term_row_s,
      column_o => term_column_s,
      write_o => term_write_s,
      character_o => term_character_s,
      foreground_o => term_foreground_s
      );

end architecture;
