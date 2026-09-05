library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_i2c, nsl_smi, nsl_time, nsl_dvi;
use nsl_dvi.terminal.all;

package func is

  -- Label screen layout on a 16x8 terminal: a status row of glyphs,
  -- each with its own color, then one value per row.
  constant screen_color_background_c : natural := 0;
  constant screen_color_value_c : natural := 1;
  constant screen_color_heart_c : natural := 2;
  constant screen_color_link_c : natural := 3;
  constant screen_color_gps_c : natural := 4;
  constant screen_color_pulse_c : natural := 5;
  constant screen_color_time_c : natural := 6;
  constant screen_color_pps_c : natural := 7;
  constant screen_color_tacc_c : natural := 8;
  constant screen_color_class_c : natural := 9;
  constant screen_color_count_c : natural := 10;

  constant screen_labels_c : label_vector(0 to 10) := (
    text_label(0, 0, 1, screen_color_heart_c, screen_color_background_c),
    text_label(0, 2, 4, screen_color_link_c, screen_color_background_c),
    text_label(0, 7, 4, screen_color_gps_c, screen_color_background_c),
    text_label(0, 12, 4, screen_color_pulse_c, screen_color_background_c),
    text_label(1, 0, 16, screen_color_time_c, screen_color_background_c),
    text_label(2, 0, 16, screen_color_time_c, screen_color_background_c),
    text_label(3, 0, 16, screen_color_pps_c, screen_color_background_c),
    text_label(4, 0, 16, screen_color_value_c, screen_color_background_c),
    text_label(5, 0, 16, screen_color_value_c, screen_color_background_c),
    text_label(6, 0, 16, screen_color_tacc_c, screen_color_background_c),
    text_label(7, 0, 16, screen_color_class_c, screen_color_background_c)
    );

  constant screen_text_length_c : natural := labels_text_length(screen_labels_c);

  component func_main is
    generic(
      clock_hz_c : natural;
      rtc_hz_c : natural := 125000000;
      gps_baud_c : natural := 9600;
      -- Above this reported time accuracy, in nanoseconds, the
      -- receiver is not trusted for discipline.
      tacc_max_ns_c : natural := 10000;
      -- When true, the servo frequency correction steers the VCXO
      -- through the DAC and the RTC increment stays nominal. When
      -- false, the correction steers the increment and the DAC is
      -- parked at midscale.
      dac_discipline_c : boolean := true;
      -- Frequency swing of the VCXO over the full DAC range, and
      -- tuning slope sign.
      dac_full_scale_ppb_c : natural := 100000;
      dac_invert_c : boolean := false;
      dac_address_c : integer range 0 to 7 := 0;
      -- Pulse path latencies: pin edge to its sampling in the time base
      -- domain, and boundary to the pin edge of the local pulse.
      pps_input_delay_ns_c : natural := 42;
      pps_output_lead_ns_c : natural := 27
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      rtc_clock_i : in std_ulogic;

      -- Layer-1 driver streams and SFD strobes, clock_i domain.
      l1_rx_i : in nsl_amba.axi4_stream.master_t;
      l1_rx_o : out nsl_amba.axi4_stream.slave_t;
      l1_tx_o : out nsl_amba.axi4_stream.master_t;
      l1_tx_i : in nsl_amba.axi4_stream.slave_t;
      rx_sfd_i : in std_ulogic;
      tx_sfd_i : in std_ulogic;

      smi_o : out nsl_smi.smi.smi_master_o;
      smi_i : in nsl_smi.smi.smi_master_i;

      -- VCXO trim DAC bus, clock_i domain.
      xo_i2c_o : out nsl_i2c.i2c.i2c_o;
      xo_i2c_i : in nsl_i2c.i2c.i2c_i;

      -- GPS, gps_txd_i is receiver to FPGA.
      gps_txd_i : in std_ulogic;
      gps_rxd_o : out std_ulogic;
      gps_pps_i : in std_ulogic;
      -- External reference pulse, only measured.
      aux_pps_i : in std_ulogic := '0';
      gps_extint_o : out std_ulogic;
      gps_reset_n_o : out std_ulogic;
      gps_safeboot_n_o : out std_ulogic;
      gps_dsel_o : out std_ulogic;

      -- Local second boundary, rtc_clock_i domain, rising edge on
      -- the boundary.
      pps_o : out std_ulogic;

      -- Heartbeat, link up, GPS locked, PPS activity
      led_o : out std_ulogic_vector(0 to 3);

      -- Observation points
      link_up_o : out std_ulogic;
      gps_locked_o : out std_ulogic;
      -- Receiver byte and decoded NAV-TIMEGPS frame strobes, one
      -- rtc_clock_i cycle each.
      gps_byte_o : out std_ulogic;
      ubx_frame_o : out std_ulogic;
      -- PPS discipline events, one rtc_clock_i cycle each: pulse seen,
      -- boundary realigned, offset handed to the servo, second set.
      pps_tick_o : out std_ulogic;
      pps_adj_o : out std_ulogic;
      pps_offset_valid_o : out std_ulogic;
      second_set_o : out std_ulogic;
      -- Servo's view of the last PPS, rtc_clock_i domain.
      pps_offset_o : out nsl_time.timestamp.timestamp_nanosecond_offset_t;
      -- Time base at the last external reference pulse, and its strobe.
      aux_offset_o : out nsl_time.timestamp.timestamp_nanosecond_offset_t;
      aux_pulse_o : out std_ulogic;
      -- rtc_clock_i domain
      second_o : out unsigned(31 downto 0);
      tacc_o : out unsigned(31 downto 0);
      freq_ppb_o : out nsl_time.discipline.frequency_ppb_t;
      -- DAC bus activity, clock_i domain, one cycle per frame end:
      -- initer command, updater command, transactor response.
      dac_init_frame_o : out std_ulogic;
      dac_update_frame_o : out std_ulogic;
      dac_response_o : out std_ulogic;
      -- DAC code override, clock_i domain; dac_o is the applied code.
      dac_force_i : in unsigned(11 downto 0) := (others => '0');
      dac_force_valid_i : in std_ulogic := '0';
      -- clock_i domain
      dac_o : out unsigned(11 downto 0);
      -- Announced time properties, clock_i domain.
      utc_offset_o : out signed(15 downto 0);
      utc_offset_valid_o : out std_ulogic;
      clock_class_o : out unsigned(7 downto 0)
      );
  end component;

  component screen_text is
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      link_up_i : in std_ulogic;
      gps_locked_i : in std_ulogic;
      -- One-cycle pulses: local second boundary, receiver pulse seen
      local_tick_i : in std_ulogic;
      gps_tick_i : in std_ulogic;
      -- PTP time base second and the announced UTC offset
      second_i : in unsigned(31 downto 0);
      utc_offset_i : in signed(15 downto 0);
      utc_offset_valid_i : in std_ulogic;
      pps_offset_i : in nsl_time.timestamp.timestamp_nanosecond_offset_t;
      aux_offset_i : in nsl_time.timestamp.timestamp_nanosecond_offset_t;
      freq_ppb_i : in nsl_time.discipline.frequency_ppb_t;
      tacc_i : in unsigned(31 downto 0);
      clock_class_i : in unsigned(7 downto 0);
      dac_i : in unsigned(11 downto 0);

      -- Label screen contents, laid out as screen_labels_c
      text_o : out string(1 to screen_text_length_c);
      colors_o : out label_color_vector(0 to screen_color_count_c-1)
      );
  end component;

end package;
