library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_mii, nsl_clocking, nsl_smi, nsl_hwdep, nsl_i2c,
  nsl_io, nsl_time, nsl_digilent, nsl_dvi, nsl_indication, nsl_color,
  gatecap_generated, work;
use nsl_amba.axi4_stream.all;
use nsl_mii.flit.all;
use nsl_time.discipline.all;
use nsl_time.timestamp.all;
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

    -- ArtySync shield
    vcxo_clock_i : in std_ulogic;
    -- The VCXO on the as-fabricated JP1 route, observation only.
    vcxo_a_clock_i : in std_ulogic;
    gps_txd_i : in std_ulogic;
    gps_rxd_o : out std_ulogic;
    gps_pps_i : in std_ulogic;
    gps_extint_o : out std_ulogic;
    gps_reset_n_o : out std_ulogic;
    gps_safeboot_n_o : out std_ulogic;
    gps_dsel_o : out std_ulogic;
    pps_o : out std_ulogic;
    -- External reference pulse on the AUX SMA, measured only.
    aux_i : in std_ulogic;

    xo_sda_io : inout std_logic;
    xo_scl_io : inout std_logic;
    -- Enables of the Arty's header I2C pull-ups.
    xo_sda_pu_o : out std_ulogic;
    xo_scl_pu_o : out std_ulogic;

    -- 10 MHz reference port, here driven toward the SMA.
    ref10m_dir_o : out std_ulogic;
    ref10m_p_io : inout std_logic;
    ref10m_n_io : inout std_logic;

    -- Pmod OLEDrgb status screen
    ja_io: inout nsl_digilent.pmod.pmod_double_t;

    btn_i: in std_ulogic_vector(0 to 3);
    ld_o: out std_ulogic_vector(4 to 7)
    );
end entity;

architecture beh of fpga_io is

  constant clock_hz_c : natural := 100000000;
  constant rtc_hz_c : natural := 125000000;
  -- Time base source: the VCXO through its PLL with DAC discipline,
  -- or the board oscillator with increment steering.  The board
  -- oscillator is only a fallback: its error exceeds the servo's
  -- authority, the loop cannot lock on it.
  constant rtc_from_vcxo_c : boolean := true;

  constant color_palette_c : rgb24_vector(0 to 7) := (
    rgb24_black,
    rgb24_red,
    rgb24_lime,
    rgb24_blue,
    rgb24_yellow,
    rgb24_cyan,
    rgb24_magenta,
    rgb24_white);

  signal clock_25_s, clock_100_s, rtc_clock_s : std_ulogic;
  signal rtc_source_s : std_ulogic;

  function rtc_input_hz return natural is
  begin
    if rtc_from_vcxo_c then
      return 20_000_000;
    end if;
    return 100_000_000;
  end function;

  constant rtc_input_hz_c : natural := rtc_input_hz;
  signal reset_n_25_s, rtc_locked_s, reset_n_s : std_ulogic;
  signal ext_reset_n_s, int_reset_n_s, eth_tx_er_s : std_ulogic;
  signal eth_smi_s : nsl_smi.smi.smi_master_i;
  signal eth_smi_c : nsl_smi.smi.smi_master_o;

  signal mii_rx_s, mii_tx_s : bus_t;
  signal rx_sfd_s, tx_sfd_s : std_ulogic;

  signal led_s : std_ulogic_vector(0 to 3);

  signal rtc_reset_n_s, user_reset_s : std_ulogic;
  signal gps_rxd_s, gps_extint_s, pps_s : std_ulogic;
  signal link_up_s, gps_locked_s : std_ulogic;
  signal second_s, tacc_s : unsigned(31 downto 0);
  signal freq_ppb_s : frequency_ppb_t;
  signal dac_s, dac_force_s : unsigned(11 downto 0);
  signal dac_force_en_s : std_ulogic;
  signal pps_offset_s, aux_offset_s : timestamp_nanosecond_offset_t;
  signal gps_pps_tick_s, local_pps_tick_s : std_ulogic;
  -- rtc-domain events crossed to the panel clock, in tick-in order:
  -- gps_byte, ubx_frame, pps_tick, pps_adj, pps_offset_valid,
  -- second_set, aux_pps.
  signal rtc_event_s, sys_event_s : std_ulogic_vector(0 to 6);
  signal xo_i2c_s : nsl_i2c.i2c.i2c_io;
  signal ref_out_s : nsl_io.diff.diff_pair;
  signal phy_reset_n_s : std_ulogic;
  signal utc_offset_s : signed(15 downto 0);
  signal utc_offset_valid_s : std_ulogic;
  signal clock_class_s : unsigned(7 downto 0);
  signal sof_s, sol_s, pixel_ready_s, pixel_valid_s : std_ulogic;
  signal pixel_s : rgb24;
  signal screen_text_s : string(1 to work.func.screen_text_length_c);
  signal screen_colors_s : nsl_dvi.terminal.label_color_vector(0 to work.func.screen_color_count_c-1);
  signal dac_init_frame_s, dac_update_frame_s, dac_response_s : std_ulogic;
  -- second, tacc, freq_ppb, pps_offset and aux_offset concatenated
  -- for one settled crossing toward the panel.
  signal panel_rtc_s, panel_sys_s : std_ulogic_vector(151 downto 0);

  signal eth_tx_en_s : std_ulogic;
  signal eth_txd_s : std_ulogic_vector(3 downto 0);
  
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

  -- The VCXO through JP1 position B; an SRCC pin, so the PLL sits in
  -- its clock region.
  rtc_source_s <= vcxo_clock_i when rtc_from_vcxo_c else clock_100_s;

  rtc_pll: nsl_clocking.pll.pll_basic
    generic map(
      input_hz_c => rtc_input_hz_c,
      output_hz_c => 125e6,
      hw_variant_c => "series67(type=pll)"
      )
    port map(
      clock_i => rtc_source_s,
      clock_o => rtc_clock_s,
      reset_n_i => int_reset_n_s,
      locked_o => rtc_locked_s
      );

  int_reset_gen: nsl_hwdep.reset.reset_at_startup
    port map(
      clock_i => clock_100_s,
      reset_n_o => int_reset_n_s
      );

  -- The whole design waits for the time base PLL.
  ext_reset_n_s <= int_reset_n_s and rtc_locked_s and not btn_i(0)
                   and not user_reset_s;
  reset_sync: nsl_clocking.async.async_edge
    port map(
      clock_i => clock_100_s,
      data_i => ext_reset_n_s,
      data_o => reset_n_s
      );

  eth_reset_n_o <= '0' when reset_n_25_s = '0' else 'Z';

  phy_ref_clock: nsl_io.clock.clock_output_se_to_se
    port map(
      clock_i => clock_25_s,
      port_o => eth_ref_clk_o
      );

  main_inst: work.func.func_main
    generic map(
      clock_hz_c => clock_hz_c,
      rtc_hz_c => rtc_hz_c,
      dac_discipline_c => rtc_from_vcxo_c,
      -- Measured against an external counter: 6.3 ppb per code,
      -- linear over the middle half of the range, nominal at 0x80a.
      dac_full_scale_ppb_c => 25800,
      -- MCP4726-A0: the address is the ordering suffix, the shield
      -- ties pin 6, VREF, to VDD.
      dac_address_c => 0
      )
    port map(
      clock_i => clock_100_s,
      reset_n_i => reset_n_s,

      rtc_clock_i => rtc_clock_s,

      l1_rx_i => mii_rx_s.m,
      l1_rx_o => mii_rx_s.s,
      l1_tx_o => mii_tx_s.m,
      l1_tx_i => mii_tx_s.s,
      rx_sfd_i => rx_sfd_s,
      tx_sfd_i => tx_sfd_s,

      smi_o => eth_smi_c,
      smi_i => eth_smi_s,

      xo_i2c_o => xo_i2c_s.o,
      xo_i2c_i => xo_i2c_s.i,

      gps_txd_i => gps_txd_i,
      gps_rxd_o => gps_rxd_s,
      gps_pps_i => gps_pps_i,
      aux_pps_i => aux_i,
      gps_extint_o => gps_extint_s,
      gps_reset_n_o => gps_reset_n_o,
      gps_safeboot_n_o => gps_safeboot_n_o,
      gps_dsel_o => gps_dsel_o,

      pps_o => pps_s,

      led_o => led_s,

      link_up_o => link_up_s,
      gps_locked_o => gps_locked_s,
      second_o => second_s,
      tacc_o => tacc_s,
      freq_ppb_o => freq_ppb_s,
      gps_byte_o => rtc_event_s(0),
      ubx_frame_o => rtc_event_s(1),
      pps_tick_o => rtc_event_s(2),
      pps_adj_o => rtc_event_s(3),
      pps_offset_valid_o => rtc_event_s(4),
      second_set_o => rtc_event_s(5),
      pps_offset_o => pps_offset_s,
      aux_offset_o => aux_offset_s,
      aux_pulse_o => rtc_event_s(6),
      dac_init_frame_o => dac_init_frame_s,
      dac_update_frame_o => dac_update_frame_s,
      dac_response_o => dac_response_s,
      dac_force_i => dac_force_s,
      dac_force_valid_i => dac_force_en_s,
      dac_o => dac_s,
      utc_offset_o => utc_offset_s,
      utc_offset_valid_o => utc_offset_valid_s,
      clock_class_o => clock_class_s
      );

  -- The FIN1019 in receiver direction carries the pair to the SMA:
  -- the raw VCXO clock goes out on J4 for an external counter.  The
  -- pair drives the port's 100 ohm termination straight from two
  -- low-drive LVCMOS pins.
  ref10m_dir_o <= '0';

  ref_out: nsl_io.clock.clock_output_se_to_diff
    port map(
      clock_i => vcxo_clock_i,
      pin_o => ref_out_s
      );

  ref10m_p_io <= ref_out_s.p;
  ref10m_n_io <= ref_out_s.n;

  xo_sda_pu_o <= '1';
  xo_scl_pu_o <= '1';

  xo_i2c_driver: nsl_i2c.i2c.i2c_line_driver
    port map(
      bus_io.sda => xo_sda_io,
      bus_io.scl => xo_scl_io,
      bus_o => xo_i2c_s.i,
      bus_i => xo_i2c_s.o
      );

  gps_rxd_o <= gps_rxd_s;
  gps_extint_o <= gps_extint_s;
  pps_o <= pps_s;

  ld_o(4 to 7) <= led_s(0 to 3);

  mii: nsl_mii.mii.mii_axi_driver_resync
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_100_s,

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

      rx_sfd_o => rx_sfd_s,
      tx_sfd_o => tx_sfd_s,

      rx_o => mii_rx_s.m,
      rx_i => mii_rx_s.s,

      tx_i => mii_tx_s.m,
      tx_o => mii_tx_s.s
      );

  eth_txd_o <= eth_txd_s;
  eth_tx_en_o <= eth_tx_en_s;
  
  rtc_reset_sync: nsl_clocking.async.async_edge
    port map(
      clock_i => rtc_clock_s,
      data_i => reset_n_s,
      data_o => rtc_reset_n_s
      );

  panel_rtc_s <= std_ulogic_vector(second_s)
                 & std_ulogic_vector(tacc_s)
                 & std_ulogic_vector(freq_ppb_s)
                 & std_ulogic_vector(resize(pps_offset_s, 32))
                 & std_ulogic_vector(resize(aux_offset_s, 32));

  panel_cross: nsl_clocking.interdomain.interdomain_reg
    generic map(
      data_width_c => 152,
      stable_count_c => 2
      )
    port map(
      clock_i => clock_100_s,
      data_i => panel_rtc_s,
      data_o => panel_sys_s
      );

  -- Pulse rates for the panel counters: both pulses are tens of
  -- milliseconds wide, resampling them in the host domain is safe.
  gps_pps_tick: nsl_clocking.async.async_input
    port map(
      clock_i => clock_100_s,
      reset_n_i => int_reset_n_s,
      data_i => gps_pps_i,
      rising_o => gps_pps_tick_s
      );

  local_pps_tick: nsl_clocking.async.async_input
    port map(
      clock_i => clock_100_s,
      reset_n_i => int_reset_n_s,
      data_i => pps_s,
      rising_o => local_pps_tick_s
      );

  phy_reset_sync: nsl_clocking.async.async_edge
    port map(
      clock_i => eth_rx_clk_i,
      data_i => int_reset_n_s,
      data_o => phy_reset_n_s
      );

  rtc_events: for i in rtc_event_s'range generate
    cross: nsl_clocking.interdomain.interdomain_tick
      port map(
        input_clock_i => rtc_clock_s,
        output_clock_i => clock_100_s,
        input_reset_n_i => rtc_reset_n_s,
        tick_i => rtc_event_s(i),
        tick_o => sys_event_s(i)
        );
  end generate;

  -- Gatecap rack over the chip TAP: clock rates, status panel with
  -- a remote reset, and a logic analyzer on the GPS lines and the
  -- local pulse, in the time base domain.
  observer: gatecap_generated.observer.observer_core
    generic map(
      burst_length_l2_c => 6
      )
    port map(
      clock_i => clock_100_s,
      reset_n_i => int_reset_n_s,

      rates_sys_i => clock_100_s,
      rates_rtc_i => rtc_clock_s,
      rates_vcxo_i => vcxo_clock_i,
      rates_vcxo_a_i => vcxo_a_clock_i,
      rates_mii_rx_i => eth_rx_clk_i,
      rates_mii_tx_i => eth_tx_clk_i,

      panel_sys_clock_i => clock_100_s,
      panel_reset_n_i => int_reset_n_s,
      panel_dac_force_en_o => dac_force_en_s,
      panel_dac_force_o => dac_force_s,
      panel_link_up_i => link_up_s,
      panel_gps_locked_i => gps_locked_s,
      panel_second_i => unsigned(panel_sys_s(151 downto 120)),
      panel_tacc_i => unsigned(panel_sys_s(119 downto 88)),
      panel_freq_ppb_i => unsigned(panel_sys_s(87 downto 64)),
      panel_dac_i => dac_s,
      panel_xo_sda_i => xo_i2c_s.i.sda,
      panel_xo_scl_i => xo_i2c_s.i.scl,
      panel_pps_offset_i => unsigned(panel_sys_s(63 downto 32)),
      panel_aux_offset_i => unsigned(panel_sys_s(31 downto 0)),
      panel_reset_o => user_reset_s,
      panel_gps_pps_i => gps_pps_tick_s,
      panel_local_pps_i => local_pps_tick_s,
      panel_gps_byte_i => sys_event_s(0),
      panel_ubx_frame_i => sys_event_s(1),
      panel_pps_tick_i => sys_event_s(2),
      panel_pps_adj_i => sys_event_s(3),
      panel_pps_offset_valid_i => sys_event_s(4),
      panel_second_set_i => sys_event_s(5),
      panel_aux_pps_i => sys_event_s(6),
      panel_init_frame_i => dac_init_frame_s,
      panel_update_frame_i => dac_update_frame_s,
      panel_dac_response_i => dac_response_s,

      i2c_phy_phy_clock_i => eth_rx_clk_i,
      i2c_phy_reset_n_i => phy_reset_n_s,
      i2c_phy_scl_i => xo_i2c_s.i.scl,
      i2c_phy_sda_i => xo_i2c_s.i.sda,

      mii_mii_clock_i => eth_tx_clk_i,
      mii_mii_reset_n_i => phy_reset_n_s,
      mii_mii_rxd_i => eth_rxd_i,
      mii_mii_rxen_i => eth_rx_dv_i,
      mii_mii_txd_i => eth_txd_s,
      mii_mii_txen_i => eth_tx_en_s
      );

  -- Status screen on the Pmod OLEDrgb, in the stack domain: every
  -- value shown has already crossed for the panel.
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

  terminal: nsl_dvi.terminal.terminal_labels
    generic map(
      row_count_l2_c => 3,
      column_count_l2_c => 4,
      character_count_l2_c => 8,
      color_palette_c => color_palette_c,
      font_c => nsl_indication.font_6x8.font_6x8_c,
      labels_c => work.func.screen_labels_c,
      blank_color_c => work.func.screen_color_background_c
      )
    port map(
      clock_i => clock_100_s,
      reset_n_i => reset_n_s,

      sof_i => sof_s,
      sol_i => sol_s,
      pixel_ready_i => pixel_ready_s,
      pixel_valid_o => pixel_valid_s,
      pixel_o => pixel_s,

      text_i => screen_text_s,
      color_i => screen_colors_s
      );

  screen: work.func.screen_text
    port map(
      clock_i => clock_100_s,
      reset_n_i => reset_n_s,

      link_up_i => link_up_s,
      gps_locked_i => gps_locked_s,
      local_tick_i => local_pps_tick_s,
      gps_tick_i => gps_pps_tick_s,
      second_i => unsigned(panel_sys_s(151 downto 120)),
      utc_offset_i => utc_offset_s,
      utc_offset_valid_i => utc_offset_valid_s,
      pps_offset_i => signed(panel_sys_s(62 downto 32)),
      aux_offset_i => signed(panel_sys_s(30 downto 0)),
      freq_ppb_i => signed(panel_sys_s(87 downto 64)),
      tacc_i => unsigned(panel_sys_s(119 downto 88)),
      clock_class_i => clock_class_s,
      dac_i => dac_s,

      text_o => screen_text_s,
      colors_o => screen_colors_s
      );

  mdio_driver: nsl_smi.smi.smi_master_line_driver
    port map(
      mdc_o => eth_mdc_o,
      mdio_io => eth_mdio_io,
      master_o => eth_smi_s,
      master_i => eth_smi_c
      );

end architecture;
