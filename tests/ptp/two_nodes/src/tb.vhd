library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_math, nsl_simulation, nsl_inet, nsl_mii,
  nsl_time, nsl_ptp;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;
use nsl_data.text.all;
use nsl_math.int_ext.all;
use nsl_math.fixed.all;
use nsl_inet.mac.all;
use nsl_inet.stream.all;
use nsl_inet.stream_mac.all;
use nsl_inet.stream_ethernet.all;
use nsl_mii.mii.all;
use nsl_mii.flit.all;
use nsl_mii.timestamping.all;
use nsl_time.timestamp.all;
use nsl_time.clock.all;
use nsl_time.capture.all;
use nsl_time.skew.all;
use nsl_time.discipline.all;
use nsl_ptp.ptp.all;
use nsl_ptp.stream_l2.all;

-- Two complete PTP nodes over a simulated MII wire: real layer-1
-- drivers cross-connected, timestamping shims, mac and ethernet
-- layers, a master ordinary clock on one side and, on the other, a
-- slave closing the discipline loop on its own adjustable clock.
--
-- The slave's time base lives in its own clock domain, unrelated to
-- the network stack: captures cross through the sideband
-- resynchronizers, the frequency correction through the two-clock
-- driver, the step through the applier.  The master keeps everything
-- on one clock, proving the degenerate case of the same components.
--
-- The slave starts a hundred seconds behind: the first Sync makes it
-- step near the master, then measurements keep it there.  A skew
-- measurer between the two clocks is the truth metric the bench
-- asserts on.
entity tb is
end tb;

architecture arch of tb is

  constant cfg_c : config_t := stream_config(1);
  constant hdr_c : integer_vector(0 to 0) := (0 => tag_length_c);
  constant blocks_c : integer_vector(0 to 1)
    := (tag_length_c, l2_context_length_c);
  constant groups_c : mac48_vector(0 to 0) := (0 => ptp_multicast_addr_c);

  -- One protocol second, in core clock cycles: keeps the message
  -- periods short enough to simulate.
  constant tick_hz_c : natural := 500;

  constant master_mac_c : mac48_t := from_hex("0221cafedec0");
  constant slave_mac_c : mac48_t := from_hex("0221cafedec1");
  constant master_identity_c : byte_string(0 to 7)
    := from_hex("0221cafeffdec000");
  constant slave_identity_c : byte_string(0 to 7)
    := from_hex("0221cafeffdec100");

  signal clock_s, mii_clock_s, rtc_clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 0);

  type mii_wire_t is
  record
    d : std_ulogic_vector(3 downto 0);
    en : std_ulogic;
  end record;

  signal m2s_s, s2m_s : mii_wire_t;

  signal master_time_s, slave_time_s : timestamp_t;
  signal master_force_s : timestamp_t := timestamp_zero_c;
  signal master_force_set_s : std_ulogic := '0';

  signal locked_s, offset_valid_s, step_valid_s : std_ulogic;
  signal offset_meas_s, path_delay_s : timestamp_nanosecond_offset_t;
  signal step_s, step_sync_s : timestamp_t;

  signal skew_s : timestamp_nanosecond_offset_t;

  constant master_inc_c : ufixed(7 downto -15)
    := to_ufixed(10.0, 7, -15);
  signal slave_inc_s : ufixed(7 downto -15);
  signal freq_ppb_s : frequency_ppb_t;

begin

  master_node: block is
    signal tag_to_mac_s, mac_to_tag_s : bus_t;
    signal mac_to_eth_s, eth_to_mac_s : bus_t;
    signal eth_to_ptp_s, ptp_to_eth_s : bus_t;
    signal strober_to_prefill_s, prefill_to_mii_s : bus_t;
    signal rx_sfd_s, tx_sfd_s : std_ulogic;
    signal rx_tag_sfd_s : std_ulogic;
    signal rx_tag_id_s, tx_strobe_id_s, capture_id_s : tag_id_t;
    signal tx_strobe_s, tx_cap_strobe_s, tx_done_s : std_ulogic;
    signal tx_cap_id_s : tag_id_t;
    signal capture_time_s, tx_capture_time_s : timestamp_t;
    signal tx_er_s : std_ulogic;
  begin
    mii: nsl_mii.mii.mii_axi_driver_resync
      port map(
        reset_n_i => reset_n_s,
        clock_i => clock_s,

        mii_i.rx.clk => mii_clock_s,
        mii_i.rx.d => s2m_s.d,
        mii_i.rx.dv => s2m_s.en,
        mii_i.rx.er => '0',
        mii_i.tx.clk => mii_clock_s,
        mii_i.status.crs => '0',
        mii_i.status.col => '0',
        mii_o.tx.d => m2s_s.d,
        mii_o.tx.en => m2s_s.en,
        mii_o.tx.er => tx_er_s,

        rx_sfd_o => rx_sfd_s,
        tx_sfd_o => tx_sfd_s,

        rx_o => mac_to_tag_s.m,
        rx_i => mac_to_tag_s.s,
        tx_i => prefill_to_mii_s.m,
        tx_o => prefill_to_mii_s.s
        );

    tagger: nsl_mii.timestamping.timestamping_rx_tagger
      generic map(
        config_c => axi4_flit_cfg
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        sfd_i => rx_sfd_s,
        sfd_o => rx_tag_sfd_s,
        id_o => rx_tag_id_s,

        in_i => mac_to_tag_s.m,
        in_o => mac_to_tag_s.s,
        out_o => tag_to_mac_s.m,
        out_i => tag_to_mac_s.s
        );

    capture: nsl_time.capture.timestamp_capture
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        timestamp_i => master_time_s,
        strobe_i => rx_tag_sfd_s,
        id_i => rx_tag_id_s,

        read_id_i => capture_id_s,
        read_timestamp_o => capture_time_s
        );

    strober: nsl_mii.timestamping.timestamping_tx_strober
      generic map(
        config_c => axi4_flit_cfg
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        sfd_i => tx_sfd_s,
        strobe_o => tx_strobe_s,
        id_o => tx_strobe_id_s,

        in_i => eth_to_mac_s.m,
        in_o => eth_to_mac_s.s,
        out_o => strober_to_prefill_s.m,
        out_i => strober_to_prefill_s.s
        );

    tx_resync: nsl_mii.timestamping.timestamping_sideband_resync
      port map(
        reset_n_i => reset_n_s,

        a_clock_i => clock_s,
        a_strobe_i => tx_strobe_s,
        a_id_i => tx_strobe_id_s,
        a_done_o => tx_done_s,

        b_clock_i => clock_s,
        b_strobe_o => tx_cap_strobe_s,
        b_id_o => tx_cap_id_s
        );

    tx_capture: nsl_time.capture.timestamp_capture
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        timestamp_i => master_time_s,
        strobe_i => tx_cap_strobe_s,
        id_i => tx_cap_id_s,

        read_id_i => ptp_tx_tag_id_c,
        read_timestamp_o => tx_capture_time_s
        );

    prefill: nsl_amba.axi4_stream.axi4_stream_prefill_buffer
      generic map(
        config_c => axi4_flit_cfg,
        prefill_count_c => 12
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        in_i => strober_to_prefill_s.m,
        in_o => strober_to_prefill_s.s,
        out_o => prefill_to_mii_s.m,
        out_i => prefill_to_mii_s.s
        );

    mac_rx: nsl_inet.stream_mac.stream_mac_receiver
      generic map(
        config_c => cfg_c,
        header_length_c => hdr_c
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,
        in_i => tag_to_mac_s.m,
        in_o => tag_to_mac_s.s,
        out_o => mac_to_eth_s.m,
        out_i => mac_to_eth_s.s
        );

    mac_eth: block is
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
          clock_i => clock_s,
          reset_n_i => reset_n_s,

          local_address_i => master_mac_c,

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
          clock_i => clock_s,
          reset_n_i => reset_n_s,
          in_i => eth_to_mactx_s.m,
          in_o => eth_to_mactx_s.s,
          out_o => eth_to_mac_s.m,
          out_i => eth_to_mac_s.s
          );
    end block;

    ptp: nsl_ptp.stream_l2.ptp_l2_master
      generic map(
        config_c => cfg_c,
        header_length_c => blocks_c,
        clock_i_hz_c => tick_hz_c,
        sync_period_c => 3
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        clock_identity_i => master_identity_c,

        capture_id_o => capture_id_s,
        capture_time_i => capture_time_s,

        tx_strobe_i => tx_done_s,
        tx_capture_time_i => tx_capture_time_s,

        rx_i => eth_to_ptp_s.m,
        rx_o => eth_to_ptp_s.s,
        tx_o => ptp_to_eth_s.m,
        tx_i => ptp_to_eth_s.s
        );

    time_base: nsl_time.clock.clock_adjustable
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,
        sub_nanosecond_inc_i => master_inc_c,
        timestamp_i => master_force_s,
        timestamp_set_i => master_force_set_s,
        timestamp_o => master_time_s
        );
  end block;

  slave_node: block is
    signal tag_to_mac_s, mac_to_tag_s : bus_t;
    signal mac_to_eth_s, eth_to_mac_s : bus_t;
    signal eth_to_ptp_s, ptp_to_eth_s : bus_t;
    signal strober_to_prefill_s, prefill_to_mii_s : bus_t;
    signal rx_sfd_s, tx_sfd_s : std_ulogic;
    signal rx_tag_sfd_s : std_ulogic;
    signal rx_tag_id_s, tx_strobe_id_s, capture_id_s : tag_id_t;
    signal rx_cap_strobe_s, tx_cap_strobe_s : std_ulogic;
    signal rx_cap_id_s, tx_cap_id_s : tag_id_t;
    signal tx_strobe_s, tx_done_s : std_ulogic;
    signal capture_time_s, tx_capture_time_s : timestamp_t;
    signal step_apply_s : timestamp_t;
    signal step_apply_set_s : std_ulogic;
    signal tx_er_s : std_ulogic;
  begin
    mii: nsl_mii.mii.mii_axi_driver_resync
      port map(
        reset_n_i => reset_n_s,
        clock_i => clock_s,

        mii_i.rx.clk => mii_clock_s,
        mii_i.rx.d => m2s_s.d,
        mii_i.rx.dv => m2s_s.en,
        mii_i.rx.er => '0',
        mii_i.tx.clk => mii_clock_s,
        mii_i.status.crs => '0',
        mii_i.status.col => '0',
        mii_o.tx.d => s2m_s.d,
        mii_o.tx.en => s2m_s.en,
        mii_o.tx.er => tx_er_s,

        rx_sfd_o => rx_sfd_s,
        tx_sfd_o => tx_sfd_s,

        rx_o => mac_to_tag_s.m,
        rx_i => mac_to_tag_s.s,
        tx_i => prefill_to_mii_s.m,
        tx_o => prefill_to_mii_s.s
        );

    tagger: nsl_mii.timestamping.timestamping_rx_tagger
      generic map(
        config_c => axi4_flit_cfg
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        sfd_i => rx_sfd_s,
        sfd_o => rx_tag_sfd_s,
        id_o => rx_tag_id_s,

        in_i => mac_to_tag_s.m,
        in_o => mac_to_tag_s.s,
        out_o => tag_to_mac_s.m,
        out_i => tag_to_mac_s.s
        );

    rx_resync: nsl_mii.timestamping.timestamping_sideband_resync
      port map(
        reset_n_i => reset_n_s,

        a_clock_i => clock_s,
        a_strobe_i => rx_tag_sfd_s,
        a_id_i => rx_tag_id_s,
        a_done_o => open,

        b_clock_i => rtc_clock_s,
        b_strobe_o => rx_cap_strobe_s,
        b_id_o => rx_cap_id_s
        );

    capture: nsl_time.capture.timestamp_capture
      port map(
        clock_i => rtc_clock_s,
        reset_n_i => reset_n_s,

        timestamp_i => slave_time_s,
        strobe_i => rx_cap_strobe_s,
        id_i => rx_cap_id_s,

        read_id_i => capture_id_s,
        read_timestamp_o => capture_time_s
        );

    strober: nsl_mii.timestamping.timestamping_tx_strober
      generic map(
        config_c => axi4_flit_cfg
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        sfd_i => tx_sfd_s,
        strobe_o => tx_strobe_s,
        id_o => tx_strobe_id_s,

        in_i => eth_to_mac_s.m,
        in_o => eth_to_mac_s.s,
        out_o => strober_to_prefill_s.m,
        out_i => strober_to_prefill_s.s
        );

    tx_resync: nsl_mii.timestamping.timestamping_sideband_resync
      port map(
        reset_n_i => reset_n_s,

        a_clock_i => clock_s,
        a_strobe_i => tx_strobe_s,
        a_id_i => tx_strobe_id_s,
        a_done_o => tx_done_s,

        b_clock_i => rtc_clock_s,
        b_strobe_o => tx_cap_strobe_s,
        b_id_o => tx_cap_id_s
        );

    tx_capture: nsl_time.capture.timestamp_capture
      port map(
        clock_i => rtc_clock_s,
        reset_n_i => reset_n_s,

        timestamp_i => slave_time_s,
        strobe_i => tx_cap_strobe_s,
        id_i => tx_cap_id_s,

        read_id_i => ptp_tx_tag_id_c,
        read_timestamp_o => tx_capture_time_s
        );

    prefill: nsl_amba.axi4_stream.axi4_stream_prefill_buffer
      generic map(
        config_c => axi4_flit_cfg,
        prefill_count_c => 12
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        in_i => strober_to_prefill_s.m,
        in_o => strober_to_prefill_s.s,
        out_o => prefill_to_mii_s.m,
        out_i => prefill_to_mii_s.s
        );

    mac_rx: nsl_inet.stream_mac.stream_mac_receiver
      generic map(
        config_c => cfg_c,
        header_length_c => hdr_c
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,
        in_i => tag_to_mac_s.m,
        in_o => tag_to_mac_s.s,
        out_o => mac_to_eth_s.m,
        out_i => mac_to_eth_s.s
        );

    mac_eth: block is
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
          clock_i => clock_s,
          reset_n_i => reset_n_s,

          local_address_i => slave_mac_c,

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
          clock_i => clock_s,
          reset_n_i => reset_n_s,
          in_i => eth_to_mactx_s.m,
          in_o => eth_to_mactx_s.s,
          out_o => eth_to_mac_s.m,
          out_i => eth_to_mac_s.s
          );
    end block;

    ptp: nsl_ptp.stream_l2.ptp_l2_slave
      generic map(
        config_c => cfg_c,
        header_length_c => blocks_c,
        clock_i_hz_c => tick_hz_c,
        delay_req_period_c => 2,
        sync_timeout_c => 8
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        clock_identity_i => slave_identity_c,

        capture_id_o => capture_id_s,
        capture_time_i => capture_time_s,

        tx_strobe_i => tx_done_s,
        tx_capture_time_i => tx_capture_time_s,

        rx_i => eth_to_ptp_s.m,
        rx_o => eth_to_ptp_s.s,
        tx_o => ptp_to_eth_s.m,
        tx_i => ptp_to_eth_s.s,

        offset_o => offset_meas_s,
        offset_valid_o => offset_valid_s,
        step_o => step_s,
        step_sync_o => step_sync_s,
        step_valid_o => step_valid_s,
        path_delay_o => path_delay_s,
        locked_o => locked_s
        );

    servo: nsl_time.discipline.discipline_pi_servo
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        offset_i => offset_meas_s,
        offset_valid_i => offset_valid_s,

        freq_offset_ppb_o => freq_ppb_s
        );

    inc_driver: nsl_time.discipline.discipline_clock_driver
      generic map(
        clock_hz_c => 156250000
        )
      port map(
        reset_n_i => reset_n_s,

        clock_i => clock_s,
        freq_offset_ppb_i => freq_ppb_s,

        rtc_clock_i => rtc_clock_s,
        sub_nanosecond_inc_o => slave_inc_s
        );

    stepper: nsl_time.discipline.discipline_step_applier
      port map(
        reset_n_i => reset_n_s,

        clock_i => clock_s,
        reference_i => step_s,
        sync_i => step_sync_s,
        valid_i => step_valid_s,

        rtc_clock_i => rtc_clock_s,
        timestamp_i => slave_time_s,
        timestamp_o => step_apply_s,
        timestamp_set_o => step_apply_set_s
        );

    time_base: nsl_time.clock.clock_adjustable
      port map(
        clock_i => rtc_clock_s,
        reset_n_i => reset_n_s,
        sub_nanosecond_inc_i => slave_inc_s,
        timestamp_i => step_apply_s,
        timestamp_set_i => step_apply_set_s,
        timestamp_o => slave_time_s
        );
  end block;

  -- Truth metric; the slave time enters unsynchronized, torn samples
  -- are discarded by the check.
  truth: nsl_time.skew.skew_measurer
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      reference_i => master_time_s,
      skewed_i => slave_time_s,

      offset_o => skew_s
      );

  epoch: process is
  begin
    master_force_set_s <= '0';
    wait for 2 us;
    wait until falling_edge(clock_s);
    master_force_s <= (abs_change => '1',
                       second => to_unsigned(100, 32),
                       nanosecond => (others => '0'));
    master_force_set_s <= '1';
    wait until falling_edge(clock_s);
    master_force_set_s <= '0';
    wait;
  end process;

  check: process is
    variable meas_count_v : integer := 0;
    variable worst_v, v : integer;
  begin
    wait for 50 us;

    assert locked_s = '1'
      report "Slave should have locked on the master"
      severity failure;
    assert to_integer(slave_time_s.second) >= 100
      report "Slave should have stepped near the master epoch"
      severity failure;

    -- Let the exchanges and the servo settle.
    wait for 50 us;

    -- Observe a window: measurements must keep coming, and the truth
    -- skew must stay bounded.
    worst_v := 0;
    for i in 0 to 3
    loop
      wait until offset_valid_s = '1' for 40 us;
      assert offset_valid_s = '1'
        report "Measurements should keep flowing"
        severity failure;
      meas_count_v := meas_count_v + 1;
      wait until falling_edge(clock_s);
      v := to_integer(abs(skew_s));
      -- A sample torn across a second boundary reads around a second
      -- off; the truth crossing is unsynchronized by design here.
      if v < 500000000 then
        if v > worst_v then
          worst_v := v;
        end if;
        log_info("skew " & to_string(to_integer(skew_s))
                 & " ns, offset " & to_string(to_integer(offset_meas_s))
                 & " ns, path delay " & to_string(to_integer(path_delay_s))
                 & " ns");
      end if;
      wait for 1 us;
    end loop;

    log_info("worst settled skew " & to_string(worst_v) & " ns");
    assert worst_v < 1000
      report "Truth skew should settle under the bound"
      severity failure;

    assert to_integer(path_delay_s) >= 0
      and to_integer(path_delay_s) < 20000
      report "Path delay out of plausible range"
      severity failure;

    done_s(0) <= '1';
    wait;
  end process;

  simdrv: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 3,
      reset_count => 1,
      done_count => 1
      )
    port map(
      clock_period(0) => 10 ns,
      clock_period(1) => 40 ns,
      clock_period(2) => 6400 ps,
      reset_duration => (others => 1 us),
      clock_o(0) => clock_s,
      clock_o(1) => mii_clock_s,
      clock_o(2) => rtc_clock_s,
      reset_n_o(0) => reset_n_s,
      done_i => done_s
      );

end;
