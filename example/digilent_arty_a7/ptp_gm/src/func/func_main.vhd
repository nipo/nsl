library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_bnoc, nsl_clocking, nsl_data, nsl_i2c, nsl_inet,
  nsl_logic, nsl_math, nsl_mii, nsl_ptp, nsl_smi, nsl_time, nsl_uart,
  nsl_ublox, work;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_logic.bool.all;
use nsl_math.int_ext.all;
use nsl_math.fixed.all;
use nsl_inet.mac.all;
use nsl_inet.stream.all;
use nsl_inet.stream_mac.all;
use nsl_inet.stream_ethernet.all;
use nsl_mii.flit.all;
use nsl_mii.link.all;
use nsl_mii.link_monitor.all;
use nsl_mii.timestamping.all;
use nsl_time.timestamp.all;
use nsl_time.clock.all;
use nsl_time.capture.all;
use nsl_time.pps.all;
use nsl_time.discipline.all;
use nsl_ptp.ptp.all;
use nsl_ptp.stream_l2.all;
use nsl_ublox.ubx.all;
use nsl_uart.serdes.all;

-- GPS-disciplined PTP grandmaster.  The network stack and the PTP
-- master run on clock_i; the time base, its discipline and the GPS
-- decoding run on rtc_clock_i, derived from the shield's VCXO.
-- Timestamps cross only through the sideband resynchronizers and
-- the capture files.
entity func_main is
  generic(
    clock_hz_c : natural;
    rtc_hz_c : natural := 125000000;
    gps_baud_c : natural := 9600;
    tacc_max_ns_c : natural := 10000;
    dac_discipline_c : boolean := true;
    dac_full_scale_ppb_c : natural := 100000;
    dac_invert_c : boolean := false;
    dac_address_c : integer range 0 to 7 := 0;
    pps_input_delay_ns_c : natural := 42;
    pps_output_lead_ns_c : natural := 27
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    rtc_clock_i : in std_ulogic;

    l1_rx_i : in master_t;
    l1_rx_o : out slave_t;
    l1_tx_o : out master_t;
    l1_tx_i : in slave_t;
    rx_sfd_i : in std_ulogic;
    tx_sfd_i : in std_ulogic;

    smi_o : out nsl_smi.smi.smi_master_o;
    smi_i : in nsl_smi.smi.smi_master_i;

    xo_i2c_o : out nsl_i2c.i2c.i2c_o;
    xo_i2c_i : in nsl_i2c.i2c.i2c_i;

    gps_txd_i : in std_ulogic;
    gps_rxd_o : out std_ulogic;
    gps_pps_i : in std_ulogic;
    aux_pps_i : in std_ulogic := '0';
    gps_extint_o : out std_ulogic;
    gps_reset_n_o : out std_ulogic;
    gps_safeboot_n_o : out std_ulogic;
    gps_dsel_o : out std_ulogic;

    pps_o : out std_ulogic;

    led_o : out std_ulogic_vector(0 to 3);

    link_up_o : out std_ulogic;
    gps_locked_o : out std_ulogic;
    gps_byte_o : out std_ulogic;
    ubx_frame_o : out std_ulogic;
    pps_tick_o : out std_ulogic;
    pps_adj_o : out std_ulogic;
    pps_offset_valid_o : out std_ulogic;
    second_set_o : out std_ulogic;
    pps_offset_o : out timestamp_nanosecond_offset_t;
    aux_offset_o : out timestamp_nanosecond_offset_t;
    aux_pulse_o : out std_ulogic;
    second_o : out unsigned(31 downto 0);
    tacc_o : out unsigned(31 downto 0);
    freq_ppb_o : out frequency_ppb_t;
    dac_init_frame_o : out std_ulogic;
    dac_update_frame_o : out std_ulogic;
    dac_response_o : out std_ulogic;
    dac_force_i : in unsigned(11 downto 0) := (others => '0');
    dac_force_valid_i : in std_ulogic := '0';
    dac_o : out unsigned(11 downto 0);
    utc_offset_o : out signed(15 downto 0);
    utc_offset_valid_o : out std_ulogic;
    clock_class_o : out unsigned(7 downto 0)
    );
end entity;

architecture beh of func_main is

  constant cfg_c : config_t := stream_config(1);
  constant hdr_c : integer_vector(0 to 0) := (0 => tag_length_c);
  constant blocks_c : integer_vector(0 to 1)
    := (tag_length_c, l2_context_length_c);
  constant groups_c : mac48_vector(0 to 0) := (0 => ptp_multicast_addr_c);

  constant local_mac_c : mac48_t := from_hex("0221cafe6d00");
  constant identity_c : byte_string(0 to 7) := from_hex("0221cafeff6d0000");

  constant uart_divisor_c : unsigned(15 downto 0)
    := to_unsigned(rtc_hz_c / gps_baud_c - 1, 16);

  -- UBX frame with a computed checksum, for the configuration
  -- messages sent to the receiver.
  function ubx_framed(msg_class, msg_id: byte;
                      payload: byte_string) return byte_string
  is
    alias xp : byte_string(0 to payload'length - 1) is payload;
    variable ret : byte_string(0 to payload'length + 7);
    variable ck_a, ck_b : unsigned(7 downto 0) := (others => '0');
  begin
    ret(0) := ubx_sync1_c;
    ret(1) := ubx_sync2_c;
    ret(2) := msg_class;
    ret(3) := msg_id;
    ret(4) := to_byte(payload'length mod 256);
    ret(5) := to_byte(payload'length / 256);
    ret(6 to 5 + payload'length) := xp;

    for i in 2 to 5 + payload'length
    loop
      ck_a := ck_a + unsigned(ret(i));
      ck_b := ck_b + ck_a;
    end loop;

    ret(payload'length + 6) := std_ulogic_vector(ck_a);
    ret(payload'length + 7) := std_ulogic_vector(ck_b);
    return ret;
  end function;

  function cfg_msg_payload return byte_string
  is
    variable ret : byte_string(0 to 7);
  begin
    ret(0) := ubx_class_nav_c;
    ret(1) := ubx_id_nav_timegps_c;
    ret(2 to 7) := from_hex("000100000000");
    return ret;
  end function;

  -- CFG-MSG: NAV-TIMEGPS once per navigation epoch on UART1.
  constant gps_cfg_c : byte_string
    := ubx_framed(to_byte(16#06#), to_byte(16#01#), cfg_msg_payload);

  signal rtc_reset_n_s : std_ulogic;

  -- Stack domain
  signal tag_to_clean_s, clean_to_mac_s, mac_to_eth_s, eth_to_mac_s : bus_t;
  signal eth_to_ptp_s, ptp_to_eth_s : bus_t;
  signal mac_to_tag_s, strober_out_s : bus_t;
  signal rx_tag_sfd_s, tx_strobe_s, tx_done_s : std_ulogic;
  signal rx_tag_id_s, tx_strobe_id_s, capture_id_s : tag_id_t;
  signal rx_error_s : std_ulogic;
  signal link_status_s : link_status_t;
  signal smi_cmd_s, smi_rsp_s : nsl_bnoc.framed.framed_bus;
  signal locked_stack_s : std_ulogic_vector(1 downto 0);
  signal clock_class_s : unsigned(7 downto 0);
  signal pps_led_s : std_ulogic;
  signal heartbeat_s : unsigned(26 downto 0);

  -- RTC domain
  signal rx_cap_strobe_s, tx_cap_strobe_s : std_ulogic;
  signal rx_cap_id_s, tx_cap_id_s : tag_id_t;
  signal capture_time_s, tx_capture_time_s : timestamp_t;
  signal rtc_time_s : timestamp_t;
  signal rtc_inc_s : ufixed(7 downto -15);
  signal freq_ppb_s : frequency_ppb_t;
  signal inc_ppb_s, dac_ppb_s : frequency_ppb_t;
  signal ppb_sys_s : std_ulogic_vector(frequency_ppb_t'range);
  signal dac_value_s, dac_applied_s : unsigned(11 downto 0);
  signal dac_init_done_s : std_ulogic;
  signal pps_offset_s, aux_offset_s : timestamp_nanosecond_offset_t;
  signal aux_valid_s : std_ulogic;
  signal pps_offset_valid_s, pps_tick_s : std_ulogic;
  signal pps_adj_s : timestamp_nanosecond_offset_t;
  signal pps_adj_valid_s : std_ulogic;
  signal set_time_s : timestamp_t;
  signal set_valid_s : std_ulogic;
  signal local_tick_s : std_ulogic;
  signal uart_byte_s : std_ulogic_vector(7 downto 0);
  signal uart_valid_s : std_ulogic;
  signal ubx_second_s, ubx_tacc_s : unsigned(31 downto 0);
  signal ubx_leap_s : signed(7 downto 0);
  signal ubx_leap_valid_s : std_ulogic;
  -- Leap second count and its validity, settled toward the stack.
  signal utc_rtc_s, utc_stack_s : std_ulogic_vector(8 downto 0);
  signal utc_offset_s : signed(15 downto 0);
  signal ubx_strobe_s, ubx_tow_valid_s, ubx_week_valid_s : std_ulogic;
  signal gps_locked_s : std_ulogic;
  signal tx_byte_s : std_ulogic_vector(7 downto 0);
  signal tx_byte_valid_s, tx_byte_ready_s : std_ulogic;

begin

  -- Static receiver strapping: UART + DDC protocols, no reset, no
  -- safeboot.
  gps_reset_n_o <= '1';
  gps_safeboot_n_o <= '1';
  gps_dsel_o <= '1';

  rtc_reset: nsl_clocking.async.async_edge
    port map(
      clock_i => rtc_clock_i,
      data_i => reset_n_i,
      data_o => rtc_reset_n_s
      );

  -- Network side, clock_i domain ---------------------------------

  tagger: nsl_mii.timestamping.timestamping_rx_tagger
    generic map(
      config_c => axi4_flit_cfg
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      sfd_i => rx_sfd_i,
      sfd_o => rx_tag_sfd_s,
      id_o => rx_tag_id_s,

      in_i => l1_rx_i,
      in_o => l1_rx_o,
      out_o => tag_to_clean_s.m,
      out_i => tag_to_clean_s.s
      );

  -- Errored frames are dropped after tagging, so the identifier
  -- sequence stays aligned with the strobes; the fifo also absorbs
  -- the line-to-core rate difference.
  rx_error_s <= user(axi4_flit_cfg, tag_to_clean_s.m)(0);

  rx_cleaner: nsl_amba.stream_fifo.axi4_stream_fifo_clean
    generic map(
      config_c => axi4_flit_cfg,
      fifo_word_count_l2 => 11
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      in_error_i => rx_error_s,
      in_i => tag_to_clean_s.m,
      in_o => tag_to_clean_s.s,

      out_o => clean_to_mac_s.m,
      out_i => clean_to_mac_s.s
      );

  mac_rx: nsl_inet.stream_mac.stream_mac_receiver
    generic map(
      config_c => cfg_c,
      header_length_c => hdr_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      in_i => clean_to_mac_s.m,
      in_o => clean_to_mac_s.s,
      out_o => mac_to_eth_s.m,
      out_i => mac_to_eth_s.s
      );

  eth_mac_tx: block is
    signal eth_to_mactx_s : bus_t;
  begin
    eth: nsl_inet.stream_ethernet.stream_ethernet_layer
      generic map(
        config_c => cfg_c,
        header_length_c => hdr_c,
        ethertype_c => (0 => ptp_ethertype_c),
        multicast_c => groups_c
        )
      port map(
        clock_i => clock_i,
        reset_n_i => reset_n_i,

        local_address_i => local_mac_c,

        to_l3_o(0) => eth_to_ptp_s.m,
        to_l3_i(0) => eth_to_ptp_s.s,
        from_l3_i(0) => ptp_to_eth_s.m,
        from_l3_o(0) => ptp_to_eth_s.s,

        to_l1_o => eth_to_mactx_s.m,
        to_l1_i => eth_to_mactx_s.s,
        from_l1_i => mac_to_eth_s.m,
        from_l1_o => mac_to_eth_s.s
        );

    mac_tx: nsl_inet.stream_mac.stream_mac_transmitter
      generic map(
        config_c => cfg_c,
        header_length_c => hdr_c
        )
      port map(
        clock_i => clock_i,
        reset_n_i => reset_n_i,
        in_i => eth_to_mactx_s.m,
        in_o => eth_to_mactx_s.s,
        out_o => mac_to_tag_s.m,
        out_i => mac_to_tag_s.s
        );
  end block;

  strober: nsl_mii.timestamping.timestamping_tx_strober
    generic map(
      config_c => axi4_flit_cfg
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      sfd_i => tx_sfd_i,
      strobe_o => tx_strobe_s,
      id_o => tx_strobe_id_s,

      in_i => mac_to_tag_s.m,
      in_o => mac_to_tag_s.s,
      out_o => strober_out_s.m,
      out_i => strober_out_s.s
      );

  -- The MII line has no flow control, but the PTP engine sustains
  -- well above the one-beat-per-8-cycles drain: the buffer only has
  -- to cover start-up bubbles, 12 beats is 96 cycles of slack.
  tx_prefill: nsl_amba.axi4_stream.axi4_stream_prefill_buffer
    generic map(
      config_c => axi4_flit_cfg,
      prefill_count_c => 12
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      in_i => strober_out_s.m,
      in_o => strober_out_s.s,
      out_o => l1_tx_o,
      out_i => l1_tx_i
      );

  ptp: nsl_ptp.stream_l2.ptp_l2_master
    generic map(
      config_c => cfg_c,
      header_length_c => blocks_c,
      clock_i_hz_c => clock_hz_c,
      sync_period_c => 1,
      announce_c => true,
      announce_period_c => 2
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      clock_identity_i => identity_c,
      clock_class_i => clock_class_s,
      time_source_i => ptp_time_source_gps_c,
      utc_offset_i => utc_offset_s,
      utc_offset_valid_i => utc_stack_s(8),
      traceable_i => locked_stack_s(0),

      capture_id_o => capture_id_s,
      capture_time_i => capture_time_s,

      tx_strobe_i => tx_done_s,
      tx_capture_time_i => tx_capture_time_s,

      rx_i => eth_to_ptp_s.m,
      rx_o => eth_to_ptp_s.s,
      tx_o => ptp_to_eth_s.m,
      tx_i => ptp_to_eth_s.s
      );

  monitor: nsl_mii.link_monitor.link_monitor_smi
    generic map(
      clock_i_hz_c => clock_hz_c,
      phy_type_c => PHY_DP83xxx
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i => clock_i,

      phyad_i => to_unsigned(1, 5),
      link_status_o => link_status_s,

      cmd_o => smi_cmd_s.req,
      cmd_i => smi_cmd_s.ack,
      rsp_i => smi_rsp_s.req,
      rsp_o => smi_rsp_s.ack
      );

  smi: nsl_smi.transactor.smi_framed_transactor
    generic map(
      clock_freq_c => clock_hz_c,
      mdc_freq_c => 2500000
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      smi_o => smi_o,
      smi_i => smi_i,

      cmd_i => smi_cmd_s.req,
      cmd_o => smi_cmd_s.ack,
      rsp_o => smi_rsp_s.req,
      rsp_i => smi_rsp_s.ack
      );

  -- Sidebands toward the time base --------------------------------

  rx_resync: nsl_mii.timestamping.timestamping_sideband_resync
    port map(
      reset_n_i => reset_n_i,

      a_clock_i => clock_i,
      a_strobe_i => rx_tag_sfd_s,
      a_id_i => rx_tag_id_s,
      a_done_o => open,

      b_clock_i => rtc_clock_i,
      b_strobe_o => rx_cap_strobe_s,
      b_id_o => rx_cap_id_s
      );

  tx_resync: nsl_mii.timestamping.timestamping_sideband_resync
    port map(
      reset_n_i => reset_n_i,

      a_clock_i => clock_i,
      a_strobe_i => tx_strobe_s,
      a_id_i => tx_strobe_id_s,
      a_done_o => tx_done_s,

      b_clock_i => rtc_clock_i,
      b_strobe_o => tx_cap_strobe_s,
      b_id_o => tx_cap_id_s
      );

  locked_resync: nsl_clocking.interdomain.interdomain_reg
    generic map(
      data_width_c => 2
      )
    port map(
      clock_i => clock_i,
      data_i(0) => gps_locked_s,
      data_i(1) => pps_led_s,
      data_o => locked_stack_s
      );

  -- currentUtcOffset for the Announce: TAI leads GPS by a constant,
  -- GPS leads UTC by the receiver's leap second count.
  utc_rtc_s <= ubx_leap_valid_s & std_ulogic_vector(ubx_leap_s);

  utc_resync: nsl_clocking.interdomain.interdomain_reg
    generic map(
      data_width_c => 9,
      stable_count_c => 2
      )
    port map(
      clock_i => clock_i,
      data_i => utc_rtc_s,
      data_o => utc_stack_s
      );

  utc_offset_s <= resize(signed(utc_stack_s(7 downto 0)), 16)
                  + to_signed(ptp_tai_minus_gps_c, 16);

  -- Time base and discipline, rtc_clock_i domain ------------------

  rx_capture: nsl_time.capture.timestamp_capture
    port map(
      clock_i => rtc_clock_i,
      reset_n_i => rtc_reset_n_s,

      timestamp_i => rtc_time_s,
      strobe_i => rx_cap_strobe_s,
      id_i => rx_cap_id_s,

      read_id_i => capture_id_s,
      read_timestamp_o => capture_time_s
      );

  tx_capture: nsl_time.capture.timestamp_capture
    port map(
      clock_i => rtc_clock_i,
      reset_n_i => rtc_reset_n_s,

      timestamp_i => rtc_time_s,
      strobe_i => tx_cap_strobe_s,
      id_i => tx_cap_id_s,

      read_id_i => ptp_tx_tag_id_c,
      read_timestamp_o => tx_capture_time_s
      );

  pps_src: nsl_time.discipline.discipline_pps_source
    generic map(
      input_delay_ns_c => pps_input_delay_ns_c
      )
    port map(
      clock_i => rtc_clock_i,
      reset_n_i => rtc_reset_n_s,

      enable_i => gps_locked_s,
      pps_i => gps_pps_i,

      timestamp_i => rtc_time_s,

      offset_o => pps_offset_s,
      offset_valid_o => pps_offset_valid_s,

      adj_o => pps_adj_s,
      adj_valid_o => pps_adj_valid_s,

      tick_o => pps_tick_s
      );

  -- The external reference pulse is only measured: the threshold
  -- makes every pulse report an offset, the adjustment goes nowhere.
  aux_src: nsl_time.discipline.discipline_pps_source
    generic map(
      align_threshold_ns_c => 400000000,
      input_delay_ns_c => pps_input_delay_ns_c
      )
    port map(
      clock_i => rtc_clock_i,
      reset_n_i => rtc_reset_n_s,

      pps_i => aux_pps_i,
      timestamp_i => rtc_time_s,

      offset_o => aux_offset_s,
      offset_valid_o => aux_valid_s,

      adj_o => open,
      adj_valid_o => open,
      tick_o => open
      );

  servo: nsl_time.discipline.discipline_pi_servo
    port map(
      clock_i => rtc_clock_i,
      reset_n_i => rtc_reset_n_s,

      offset_i => pps_offset_s,
      offset_valid_i => pps_offset_valid_s,

      freq_offset_ppb_o => freq_ppb_s
      );

  -- One actuator consumes the servo correction, the other one stays
  -- neutral: the increment when the DAC steers the VCXO, the DAC
  -- (parked at midscale) otherwise.
  inc_ppb_s <= (others => '0') when dac_discipline_c else freq_ppb_s;
  dac_ppb_s <= frequency_ppb_t(ppb_sys_s) when dac_discipline_c
               else (others => '0');

  inc_driver: nsl_time.discipline.discipline_clock_driver
    generic map(
      clock_hz_c => rtc_hz_c
      )
    port map(
      reset_n_i => rtc_reset_n_s,

      clock_i => rtc_clock_i,
      freq_offset_ppb_i => inc_ppb_s,

      rtc_clock_i => rtc_clock_i,
      sub_nanosecond_inc_o => rtc_inc_s
      );

  -- VCXO trim DAC, clock_i domain.  The MCP4726 gets its reference
  -- and power configuration once out of reset, then follows the
  -- servo frequency correction.  Both masters share the single I2C
  -- transactor through a framed arbiter.
  vcxo_dac: block
    signal cmd_req_s, rsp_req_s : nsl_bnoc.framed.framed_req_array(0 to 1);
    signal cmd_ack_s, rsp_ack_s : nsl_bnoc.framed.framed_ack_array(0 to 1);
    signal t_cmd_req_s, t_rsp_req_s : nsl_bnoc.framed.framed_req;
    signal t_cmd_ack_s, t_rsp_ack_s : nsl_bnoc.framed.framed_ack;
  begin
    ppb_cross: nsl_clocking.interdomain.interdomain_reg
      generic map(
        data_width_c => frequency_ppb_t'length,
        stable_count_c => 2
        )
      port map(
        clock_i => clock_i,
        data_i => std_ulogic_vector(freq_ppb_s),
        data_o => ppb_sys_s
        );

    driver: nsl_time.discipline.discipline_dac_driver
      generic map(
        dac_width_c => 12,
        full_scale_ppb_c => dac_full_scale_ppb_c,
        invert_c => dac_invert_c
        )
      port map(
        clock_i => clock_i,
        reset_n_i => reset_n_i,

        freq_offset_ppb_i => dac_ppb_s,

        dac_o => dac_value_s
        );

    dac_applied_s <= dac_force_i when dac_force_valid_i = '1' else dac_value_s;

    dac_init_frame_o <= cmd_req_s(0).valid and cmd_ack_s(0).ready and cmd_req_s(0).last;
    dac_update_frame_o <= cmd_req_s(1).valid and cmd_ack_s(1).ready and cmd_req_s(1).last;
    dac_response_o <= t_rsp_req_s.valid and t_rsp_ack_s.ready and t_rsp_req_s.last;

    initer: nsl_bnoc.framed_transactor.framed_transactor_once
      generic map(
        config_c => nsl_bnoc.framed_transactor.framed_transaction(
          null_byte_string
          -- Divisor persists in the transactor, roughly 100kHz SCL.
          & nsl_bnoc.framed_transactor.i2c_div(4)
          & nsl_i2c.mcp4726.mcp4726_init(
            saddr => nsl_i2c.mcp4726.mcp4726_addr(dac_address_c),
            vref => nsl_i2c.mcp4726.VREF_BUFFERED,
            power => nsl_i2c.mcp4726.POWER_ON,
            gain => 1,
            value => x"800")
          )
        )
      port map(
        reset_n_i => reset_n_i,
        clock_i => clock_i,

        done_o => dac_init_done_s,

        cmd_o => cmd_req_s(0),
        cmd_i => cmd_ack_s(0),
        rsp_i => rsp_req_s(0),
        rsp_o => rsp_ack_s(0)
        );

    updater: nsl_i2c.mcp4726.mcp4726_updater
      generic map(
        i2c_addr_c => nsl_i2c.mcp4726.mcp4726_addr(dac_address_c)
        )
      port map(
        reset_n_i => reset_n_i,
        clock_i => clock_i,

        enable_i => dac_init_done_s,
        value_i => dac_applied_s,

        cmd_o => cmd_req_s(1),
        cmd_i => cmd_ack_s(1),
        rsp_i => rsp_req_s(1),
        rsp_o => rsp_ack_s(1)
        );

    arbiter: nsl_bnoc.framed.framed_arbitrer
      generic map(
        source_count => 2
        )
      port map(
        p_resetn => reset_n_i,
        p_clk => clock_i,

        p_cmd_val => cmd_req_s,
        p_cmd_ack => cmd_ack_s,
        p_rsp_val => rsp_req_s,
        p_rsp_ack => rsp_ack_s,

        p_target_cmd_val => t_cmd_req_s,
        p_target_cmd_ack => t_cmd_ack_s,
        p_target_rsp_val => t_rsp_req_s,
        p_target_rsp_ack => t_rsp_ack_s
        );

    transactor: nsl_i2c.transactor.transactor_framed_controller
      generic map(
        clock_i_hz_c => clock_hz_c
        )
      port map(
        clock_i => clock_i,
        reset_n_i => reset_n_i,

        cmd_i => t_cmd_req_s,
        cmd_o => t_cmd_ack_s,
        rsp_o => t_rsp_req_s,
        rsp_i => t_rsp_ack_s,

        i2c_o => xo_i2c_o,
        i2c_i => xo_i2c_i
        );
  end block;

  uart_rx_inst: nsl_uart.serdes.uart_rx
    generic map(
      bit_count_c => 8,
      stop_count_c => 1,
      parity_c => PARITY_NONE
      )
    port map(
      clock_i => rtc_clock_i,
      reset_n_i => rtc_reset_n_s,

      divisor_i => uart_divisor_c,

      uart_i => gps_txd_i,

      data_o => uart_byte_s,
      valid_o => uart_valid_s
      );

  ubx: nsl_ublox.ubx.ubx_nav_timegps
    generic map(
      epoch_offset_c => gps_to_ptp_offset_c
      )
    port map(
      clock_i => rtc_clock_i,
      reset_n_i => rtc_reset_n_s,

      byte_i => uart_byte_s,
      valid_i => uart_valid_s,

      second_o => ubx_second_s,
      leap_s_o => ubx_leap_s,
      tow_valid_o => ubx_tow_valid_s,
      week_valid_o => ubx_week_valid_s,
      leap_valid_o => ubx_leap_valid_s,
      tacc_o => ubx_tacc_s,
      strobe_o => ubx_strobe_s
      );

  setter: nsl_time.discipline.discipline_second_setter
    port map(
      clock_i => rtc_clock_i,
      reset_n_i => rtc_reset_n_s,

      enable_i => gps_locked_s,

      second_i => ubx_second_s,
      second_valid_i => ubx_strobe_s,

      tick_i => pps_tick_s,

      timestamp_i => rtc_time_s,
      timestamp_o => set_time_s,
      timestamp_set_o => set_valid_s
      );

  time_base: nsl_time.clock.clock_adjustable
    port map(
      clock_i => rtc_clock_i,
      reset_n_i => rtc_reset_n_s,
      sub_nanosecond_inc_i => rtc_inc_s,
      nanosecond_adj_i => pps_adj_s,
      nanosecond_adj_set_i => pps_adj_valid_s,
      timestamp_i => set_time_s,
      timestamp_set_i => set_valid_s,
      timestamp_o => rtc_time_s
      );

  local_pps: nsl_time.pps.pps_ticker
    generic map(
      lead_ns_c => pps_output_lead_ns_c
      )
    port map(
      clock_i => rtc_clock_i,
      reset_n_i => rtc_reset_n_s,

      reference_i => rtc_time_s,

      tick_o => local_tick_s
      );

  -- GPS supervision: the receiver is trusted while it reports valid
  -- week and time of week with a small enough accuracy, and spoke
  -- recently.  The configuration frame enabling NAV-TIMEGPS is
  -- resent every eight seconds until frames flow.
  gps_glue: block is
    type regs_t is
    record
      locked: boolean;
      fresh: integer range 0 to 3;
      resend: integer range 0 to 7;
      tacc_ok: boolean;
      cfg_pos: integer range 0 to gps_cfg_c'length;
      pps_stretch: integer range 0 to 2 ** 22 - 1;
    end record;

    signal r, rin: regs_t;
  begin
    regs: process(rtc_clock_i, rtc_reset_n_s) is
    begin
      if rising_edge(rtc_clock_i) then
        r <= rin;
      end if;

      if rtc_reset_n_s = '0' then
        r.locked <= false;
        r.fresh <= 0;
        r.resend <= 2;
        r.tacc_ok <= false;
        r.cfg_pos <= gps_cfg_c'length;
        r.pps_stretch <= 0;
      end if;
    end process;

    transition: process(r, ubx_strobe_s, ubx_tow_valid_s, ubx_week_valid_s,
                        ubx_tacc_s, local_tick_s, tx_byte_ready_s) is
    begin
      rin <= r;

      if ubx_strobe_s = '1' then
        rin.fresh <= 3;
        rin.tacc_ok <= ubx_tacc_s < to_unsigned(tacc_max_ns_c, 32);
        rin.locked <= ubx_tow_valid_s = '1' and ubx_week_valid_s = '1'
                      and ubx_tacc_s < to_unsigned(tacc_max_ns_c, 32);
      end if;

      if local_tick_s = '1' then
        if r.fresh /= 0 then
          rin.fresh <= r.fresh - 1;
        else
          rin.locked <= false;
        end if;

        if r.fresh = 0 then
          if r.resend /= 0 then
            rin.resend <= r.resend - 1;
          else
            rin.resend <= 7;
            rin.cfg_pos <= 0;
          end if;
        end if;

        rin.pps_stretch <= 2 ** 22 - 1;
      elsif r.pps_stretch /= 0 then
        rin.pps_stretch <= r.pps_stretch - 1;
      end if;

      if r.cfg_pos /= gps_cfg_c'length
        and tx_byte_ready_s = '1' then
        rin.cfg_pos <= r.cfg_pos + 1;
      end if;
    end process;

    moore: process(r) is
    begin
      gps_locked_s <= to_logic(r.locked);
      tx_byte_valid_s <= to_logic(r.cfg_pos /= gps_cfg_c'length);
      if r.cfg_pos /= gps_cfg_c'length then
        tx_byte_s <= std_ulogic_vector(gps_cfg_c(gps_cfg_c'left + r.cfg_pos));
      else
        tx_byte_s <= (others => '0');
      end if;

      -- The rising edge marks the boundary exactly; the stretch only
      -- makes the pulse visible.  The same pulse goes to the
      -- receiver's event input, timestamped there as an independent
      -- check of the local boundary.
      pps_o <= to_logic(r.pps_stretch /= 0);
      gps_extint_o <= to_logic(r.pps_stretch /= 0);
      pps_led_s <= to_logic(r.pps_stretch /= 0);
    end process;
  end block;

  uart_tx_inst: nsl_uart.serdes.uart_tx
    generic map(
      bit_count_c => 8,
      stop_count_c => 1,
      parity_c => PARITY_NONE
      )
    port map(
      clock_i => rtc_clock_i,
      reset_n_i => rtc_reset_n_s,

      divisor_i => uart_divisor_c,

      uart_o => gps_rxd_o,

      data_i => tx_byte_s,
      ready_o => tx_byte_ready_s,
      valid_i => tx_byte_valid_s
      );

  heartbeat: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      heartbeat_s <= heartbeat_s + 1;
    end if;

    if reset_n_i = '0' then
      heartbeat_s <= (others => '0');
    end if;
  end process;

  led_o(0) <= heartbeat_s(heartbeat_s'left);
  led_o(1) <= '1' when link_status_s.up else '0';
  led_o(2) <= locked_stack_s(0);
  led_o(3) <= locked_stack_s(1);

  clock_class_s <= to_unsigned(ptp_clock_class_locked_c, 8)
                   when locked_stack_s(0) = '1'
                   else to_unsigned(ptp_clock_class_default_c, 8);

  link_up_o <= '1' when link_status_s.up else '0';
  gps_locked_o <= locked_stack_s(0);
  pps_tick_o <= pps_tick_s;
  pps_adj_o <= pps_adj_valid_s;
  pps_offset_valid_o <= pps_offset_valid_s;
  second_set_o <= set_valid_s;
  gps_byte_o <= uart_valid_s;
  ubx_frame_o <= ubx_strobe_s;
  pps_offset_o <= pps_offset_s;
  aux_offset_o <= aux_offset_s;
  aux_pulse_o <= aux_valid_s;
  second_o <= rtc_time_s.second;
  tacc_o <= ubx_tacc_s;
  freq_ppb_o <= freq_ppb_s;
  dac_o <= dac_applied_s;
  utc_offset_o <= utc_offset_s;
  utc_offset_valid_o <= utc_stack_s(8);
  clock_class_o <= clock_class_s;

end architecture;
