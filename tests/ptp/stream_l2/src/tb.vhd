library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation, nsl_amba, nsl_math, nsl_mii, nsl_inet, nsl_ptp, nsl_time;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.text.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;
use nsl_amba.axi4_stream.all;
use nsl_math.int_ext.all;
use nsl_mii.timestamping.all;
use nsl_inet.mac.all;
use nsl_inet.stream.all;
use nsl_inet.stream_ethernet.all;
use nsl_ptp.ptp.all;
use nsl_ptp.stream_l2.all;
use nsl_time.timestamp.all;

-- PTP ordinary clocks against scripted peers.  A slave is driven by a
-- bench master that scripts capture and strobe times, so every
-- measurement has a hand-computed expectation; a master is inspected
-- message by message; a third pair runs slave against master over the
-- pipes with a constant wire delay and a constant clock skew, and the
-- slave must recover both.
entity tb is
end tb;

architecture arch of tb is

  constant cfg_c : config_t := stream_config(1);
  constant hdr_c : integer_vector(0 to 1)
    := (tag_length_c, l2_context_length_c);
  constant hdr_size_c : natural := context_byte_count(cfg_c, hdr_c);

  -- Protocol second, as the engine ticker divider and as bench time
  constant engine_hz_c : natural := 1000;
  constant clock_period_c : time := 10 ns;
  constant half_ns_c : integer := 5;
  constant tick_c : time := 10 us;

  constant slave_group_c : natural := 2;
  constant master_group_c : natural := 3;

  constant master_clock_c : byte_string(0 to 7) := from_hex("0011223344556677");
  constant master2_clock_c : byte_string(0 to 7) := from_hex("00aabbccddee0102");
  constant slave_clock_c : byte_string(0 to 7) := from_hex("1000000000000001");

  constant base_sec_c : natural := 5;
  constant ns_per_second_c : natural := 1000000000;

  function port_identity(id: byte_string) return ptp_port_identity_t
  is
    alias xi: byte_string(0 to 7) is id;
    variable ret: ptp_port_identity_t;
  begin
    ret(0 to 7) := xi;
    ret(8) := x"00";
    ret(9) := x"01";
    return ret;
  end function;

  constant master_id_c : ptp_port_identity_t := port_identity(master_clock_c);
  constant master2_id_c : ptp_port_identity_t := port_identity(master2_clock_c);
  constant slave_id_c : ptp_port_identity_t := port_identity(slave_clock_c);
  constant null_id_c : ptp_port_identity_t := (others => x"00");

  function ts_of(sec: natural; ns: natural) return timestamp_t
  is
  begin
    return (abs_change => '0',
            second => to_unsigned(sec, 32),
            nanosecond => to_unsigned(ns, 30));
  end function;

  -- Bench absolute time, in nanoseconds since base_sec_c.
  function ts_of_ns(n: integer) return timestamp_t
  is
  begin
    return ts_of(base_sec_c + n / ns_per_second_c, n mod ns_per_second_c);
  end function;

  function ns_at(t: time) return integer
  is
  begin
    return t / 1 ns;
  end function;

  -- Header blocks of a packet handed to an engine: the timestamping
  -- tag then the layer-2 context.  Engines take their receive time
  -- from the capture register the tag designates and skip the
  -- context, so its contents only need to be well formed.
  constant rx_prefix_c : byte_string(0 to hdr_size_c-1)
    := byte_string'(0 => tag_build(false, "0011"))
       & to_bytes(l2_context_t'(peer => ptp_multicast_addr_c,
                                casting => l2_multicast(slave_group_c)));

  -- correctionField, nanoseconds scaled by 2**16.
  function correction_bytes(ns: integer) return byte_string
  is
    variable ret: byte_string(0 to 7) := (others => x"00");
  begin
    if ns < 0 then
      ret(0 to 1) := (others => x"ff");
    end if;
    ret(2 to 5) := to_be(unsigned(to_signed(ns, 32)));
    return ret;
  end function;

  function ptp_message(msg_type: natural;
                       seq: natural;
                       source: ptp_port_identity_t;
                       ts: timestamp_t;
                       correction: integer := 0;
                       two_step: boolean := false;
                       req_id: ptp_port_identity_t := (others => x"00"))
    return byte_string
  is
    variable ret: byte_string(0 to ptp_delay_resp_length_c-1)
      := (others => x"00");
    variable len_v: natural;
  begin
    if msg_type = ptp_msg_delay_resp_c then
      len_v := ptp_delay_resp_length_c;
    else
      len_v := ptp_sync_length_c;
    end if;

    ret(ptp_off_type_c) := to_byte(msg_type);
    ret(ptp_off_version_c) := to_byte(2);
    ret(ptp_off_length_c to ptp_off_length_c+1)
      := to_be(to_unsigned(len_v, 16));
    if two_step then
      ret(ptp_off_flags_c) := to_byte(2 ** ptp_flag0_two_step_c);
    end if;
    ret(ptp_off_correction_c to ptp_off_correction_c+7)
      := correction_bytes(correction);
    ret(ptp_off_source_port_identity_c to ptp_off_source_port_identity_c+9)
      := source;
    ret(ptp_off_sequence_id_c to ptp_off_sequence_id_c+1)
      := to_be(to_unsigned(seq, 16));
    ret(ptp_off_timestamp_c to ptp_off_timestamp_c+9) := to_ptp_timestamp(ts);
    if msg_type = ptp_msg_delay_resp_c then
      ret(ptp_off_requesting_port_identity_c
          to ptp_off_requesting_port_identity_c+9) := req_id;
    end if;

    return ret(0 to len_v-1);
  end function;

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 2);

  -- Value the transmit capture file holds outside the window where a
  -- strobed frame's departure time is presented.
  constant decoy_ts_c : timestamp_t := ts_of(9, 999999999);

  -- Scripted slave
  signal s_rx_s, s_tx_s : bus_t;
  signal s_cap_s : timestamp_t := timestamp_zero_c;
  -- Departure time the bench will present for the next strobed frame
  signal s_t3_s : timestamp_t := timestamp_zero_c;
  signal s_txcap_s : timestamp_t := decoy_ts_c;
  signal s_strobe_s : std_ulogic := '0';
  signal s_txbuf_s : byte_string(0 to 63) := (others => x"00");
  signal s_txlen_s : natural := 0;
  signal s_txcnt_s : natural := 0;
  signal s_offset_s, s_pdelay_s : timestamp_nanosecond_offset_t;
  signal s_offset_valid_s, s_step_valid_s, s_locked_s : std_ulogic;
  signal s_step_s, s_step_sync_s : timestamp_t;
  signal s_off_last_s : timestamp_nanosecond_offset_t;
  signal s_off_cnt_s : natural := 0;
  signal s_step_last_s, s_step_sync_last_s : timestamp_t;
  signal s_step_cnt_s : natural := 0;

  -- Scripted master
  signal m_rx_s, m_tx_s : bus_t;
  signal m_cap_s : timestamp_t := timestamp_zero_c;
  signal m_t1_s : timestamp_t := timestamp_zero_c;
  signal m_txcap_s : timestamp_t := decoy_ts_c;
  signal m_strobe_s : std_ulogic := '0';
  signal m_txbuf_s : byte_string(0 to 63) := (others => x"00");
  signal m_txlen_s : natural := 0;
  signal m_txcnt_s : natural := 0;

  -- Back to back pair
  constant bb_delay_c : integer := 1200;
  constant bb_skew_c : integer := 3500;
  signal bb_m2s_s, bb_s2m_s : bus_t;
  signal bb_scap_s, bb_mcap_s : timestamp_t := timestamp_zero_c;
  signal bb_stxcap_s, bb_mtxcap_s : timestamp_t := timestamp_zero_c;
  signal bb_sstrobe_s, bb_mstrobe_s : std_ulogic := '0';
  signal bb_offset_s, bb_pdelay_s : timestamp_nanosecond_offset_t;
  signal bb_offset_valid_s, bb_step_valid_s, bb_locked_s : std_ulogic;
  signal bb_step_s, bb_step_sync_s : timestamp_t;
  signal bb_off_last_s : timestamp_nanosecond_offset_t;
  signal bb_off_cnt_s : natural := 0;

begin

  -- Scripted slave: bench master
  ----------------------------------------------------------------

  slave_tx_mon: process is
    variable beat_v: master_t;
    variable buf_v: byte_string(0 to 63);
    variable n_v: natural;
  begin
    s_tx_s.s <= accept(cfg_c, false);
    s_strobe_s <= '0';
    s_txcap_s <= decoy_ts_c;
    wait for 100 ns;

    loop
      n_v := 0;
      buf_v := (others => x"00");
      loop
        receive(cfg_c, clock_s, s_tx_s.m, s_tx_s.s, beat_v);
        buf_v(n_v) := beat_v.data(0);
        n_v := n_v + 1;
        exit when is_last(cfg_c, beat_v);
      end loop;

      s_txbuf_s <= buf_v;
      s_txlen_s <= n_v;
      s_txcnt_s <= s_txcnt_s + 1;

      if tag_strobes(buf_v(0)) then
        -- The capture register is written first, the done strobe
        -- follows.  The value is only presented for the strobe cycle,
        -- so an engine reading the capture file at any other time
        -- cannot pass unnoticed.
        s_txcap_s <= s_t3_s;
        wait until rising_edge(clock_s);
        s_strobe_s <= '1';
        wait until rising_edge(clock_s);
        s_strobe_s <= '0';
        s_txcap_s <= decoy_ts_c;
      end if;
    end loop;
  end process;

  slave_latch: process(clock_s) is
  begin
    if rising_edge(clock_s) then
      if s_offset_valid_s = '1' then
        s_off_last_s <= s_offset_s;
        s_off_cnt_s <= s_off_cnt_s + 1;
      end if;

      if s_step_valid_s = '1' then
        s_step_last_s <= s_step_s;
        s_step_sync_last_s <= s_step_sync_s;
        s_step_cnt_s <= s_step_cnt_s + 1;
      end if;
    end if;
  end process;

  slave_script: process is
    constant t1a_c : timestamp_t := ts_of(base_sec_c, 100000);
    constant t2a_c : timestamp_t := ts_of(base_sec_c, 101500);
    constant t3a_c : timestamp_t := ts_of(base_sec_c, 200000);
    constant t4a_c : timestamp_t := ts_of(base_sec_c, 200400);
    constant t1b_c : timestamp_t := ts_of(base_sec_c, 300000);
    constant t2b_c : timestamp_t := ts_of(base_sec_c, 301500);
    -- Corrections shift the master origin by -300 + 200 ns
    constant t1c_c : timestamp_t := ts_of(base_sec_c, 400000);
    constant t2c_c : timestamp_t := ts_of(base_sec_c, 402000);
    constant t1d_c : timestamp_t := ts_of(base_sec_c, 500000);
    constant t2d_c : timestamp_t := ts_of(base_sec_c, 503000);
    constant t1e_c : timestamp_t := ts_of(base_sec_c, 600000);
    constant t2e_c : timestamp_t := ts_of(base_sec_c, 604000);
    constant t1f_c : timestamp_t := ts_of(base_sec_c, 100000000);
    constant t2f_c : timestamp_t := ts_of(base_sec_c, 500000000);
    constant t1g_c : timestamp_t := ts_of(base_sec_c, 700000);
    constant t2g_c : timestamp_t := ts_of(base_sec_c, 702500);

    variable txn_v: natural := 0;
    variable dreq_seq_v: natural;

    procedure rx_send(constant msg: byte_string;
                      constant capture: timestamp_t) is
    begin
      s_cap_s <= capture;
      wait until rising_edge(clock_s);
      packet_send(cfg_c, clock_s, s_rx_s.s, s_rx_s.m,
                  packet => rx_prefix_c & msg,
                  user => "0");
      wait until rising_edge(clock_s);
    end procedure;

    procedure dreq_get is
    begin
      if s_txcnt_s = txn_v then
        wait until s_txcnt_s /= txn_v;
      end if;
      txn_v := s_txcnt_s;
      wait until rising_edge(clock_s);
    end procedure;

    -- Byte of the emitted message.
    impure function pb(k: integer) return byte is
    begin
      return s_txbuf_s(hdr_size_c + k);
    end function;

    impure function ps(f, l: integer) return byte_string is
    begin
      return s_txbuf_s(hdr_size_c + f to hdr_size_c + l);
    end function;

    procedure offset_expect(constant what: string;
                            constant count: natural;
                            constant offset: integer;
                            constant path_delay: integer) is
    begin
      if s_off_cnt_s /= count then
        wait until s_off_cnt_s = count for 20 us;
      end if;
      assert_equal(what & " measurement count", s_off_cnt_s, count, failure);
      assert_equal(what & " offset", to_integer(s_off_last_s), offset, failure);
      assert_equal(what & " path delay", to_integer(s_pdelay_s), path_delay,
                   failure);
    end procedure;
  begin
    s_rx_s.m <= transfer_defaults(cfg_c);
    s_t3_s <= t3a_c;
    wait for 100 ns;

    assert_equal("initial lock", s_locked_s, '0', failure);

    -- Two-step sync, no path delay known yet
    rx_send(ptp_message(ptp_msg_sync_c, 1, master_id_c, timestamp_zero_c,
                        two_step => true),
            t2a_c);
    wait for 1 us;
    assert_equal("lock on first sync", s_locked_s, '1', failure);

    rx_send(ptp_message(ptp_msg_follow_up_c, 1, master_id_c, t1a_c),
            t2a_c);
    offset_expect("first sync", 1, 1500, 0);

    -- Delay request exchange
    dreq_get;
    assert_equal("delay request length", s_txlen_s,
                 hdr_size_c + ptp_delay_req_length_c, failure);
    assert tag_strobes(s_txbuf_s(0))
      report "Delay_Req must request the transmit strobe"
      severity failure;
    assert_equal("delay request tag id", tag_id(s_txbuf_s(0)),
                 ptp_tx_tag_id_c, failure);
    assert_equal("delay request peer", s_txbuf_s(tag_length_c
                                                 to tag_length_c+5),
                 ptp_multicast_addr_c, failure);
    assert_equal("delay request casting", s_txbuf_s(tag_length_c+6),
                 l2_multicast(slave_group_c), failure);
    assert_equal("delay request type", pb(ptp_off_type_c),
                 to_byte(ptp_msg_delay_req_c), failure);
    assert_equal("delay request version", pb(ptp_off_version_c), to_byte(2),
                 failure);
    assert_equal("delay request length field",
                 to_integer(from_be(ps(ptp_off_length_c,
                                       ptp_off_length_c+1))),
                 ptp_delay_req_length_c, failure);
    assert_equal("delay request domain", pb(ptp_off_domain_c), to_byte(0),
                 failure);
    assert_equal("delay request source",
                 ps(ptp_off_source_port_identity_c,
                    ptp_off_source_port_identity_c+9),
                 slave_id_c, failure);
    assert_equal("delay request control", pb(ptp_off_control_c), to_byte(1),
                 failure);
    dreq_seq_v := to_integer(from_be(ps(ptp_off_sequence_id_c,
                                        ptp_off_sequence_id_c+1)));

    rx_send(ptp_message(ptp_msg_delay_resp_c, dreq_seq_v, master_id_c, t4a_c,
                        req_id => slave_id_c),
            timestamp_zero_c);
    wait for 2 us;
    assert_equal("mean path delay", to_integer(s_pdelay_s), 950, failure);

    -- Measurement with a known path delay
    rx_send(ptp_message(ptp_msg_sync_c, 2, master_id_c, timestamp_zero_c,
                        two_step => true),
            t2b_c);
    rx_send(ptp_message(ptp_msg_follow_up_c, 2, master_id_c, t1b_c), t2b_c);
    offset_expect("delay corrected sync", 2, 550, 950);

    -- Correction fields fold into the master origin
    rx_send(ptp_message(ptp_msg_sync_c, 3, master_id_c, timestamp_zero_c,
                        correction => -300, two_step => true),
            t2c_c);
    rx_send(ptp_message(ptp_msg_follow_up_c, 3, master_id_c, t1c_c,
                        correction => 200),
            t2c_c);
    offset_expect("corrected sync", 3, 1150, 950);

    -- One-step sync
    rx_send(ptp_message(ptp_msg_sync_c, 4, master_id_c, t1d_c), t2d_c);
    offset_expect("one step sync", 4, 2050, 950);

    -- A second master is ignored while locked
    rx_send(ptp_message(ptp_msg_sync_c, 100, master2_id_c, timestamp_zero_c,
                        two_step => true),
            ts_of(base_sec_c, 900000));
    rx_send(ptp_message(ptp_msg_follow_up_c, 100, master2_id_c,
                        ts_of(base_sec_c, 800000)),
            ts_of(base_sec_c, 900000));
    wait for 3 us;
    assert_equal("foreign master ignored", s_off_cnt_s, 4, failure);
    assert_equal("lock kept", s_locked_s, '1', failure);

    -- A stale follow up must not complete the pending sync
    rx_send(ptp_message(ptp_msg_sync_c, 5, master_id_c, timestamp_zero_c,
                        two_step => true),
            t2e_c);
    rx_send(ptp_message(ptp_msg_follow_up_c, 4, master_id_c,
                        ts_of(base_sec_c, 595000)),
            t2e_c);
    wait for 3 us;
    assert_equal("stale follow up ignored", s_off_cnt_s, 4, failure);
    rx_send(ptp_message(ptp_msg_follow_up_c, 5, master_id_c, t1e_c), t2e_c);
    offset_expect("resequenced sync", 5, 3050, 950);

    -- Beyond the step threshold, a clock set is requested instead:
    -- the master time of the Sync's departure plus the path delay,
    -- with the local arrival time of that Sync alongside.
    assert_equal("no step yet", s_step_cnt_s, 0, failure);
    rx_send(ptp_message(ptp_msg_sync_c, 6, master_id_c, timestamp_zero_c,
                        two_step => true),
            t2f_c);
    rx_send(ptp_message(ptp_msg_follow_up_c, 6, master_id_c, t1f_c), t2f_c);
    if s_step_cnt_s = 0 then
      wait until s_step_cnt_s = 1 for 20 us;
    end if;
    assert_equal("step requested", s_step_cnt_s, 1, failure);
    assert_equal("no offset on step", s_off_cnt_s, 5, failure);
    assert_equal("step second", s_step_last_s.second,
                 to_unsigned(base_sec_c, 32), failure);
    assert_equal("step nanosecond", to_integer(s_step_last_s.nanosecond),
                 100000950, failure);
    assert_equal("step is absolute", s_step_last_s.abs_change, '1', failure);
    assert_equal("step sync second", s_step_sync_last_s.second,
                 t2f_c.second, failure);
    assert_equal("step sync nanosecond", s_step_sync_last_s.nanosecond,
                 t2f_c.nanosecond, failure);

    -- Delay request sequence numbers move on
    dreq_get;
    assert_equal("delay request sequence",
                 to_integer(from_be(ps(ptp_off_sequence_id_c,
                                       ptp_off_sequence_id_c+1))),
                 dreq_seq_v + 1, failure);

    -- Sync starvation drops the lock
    if s_locked_s = '1' then
      wait until s_locked_s = '0' for 100 us;
    end if;
    assert_equal("lock lost on starvation", s_locked_s, '0', failure);
    assert_equal("path delay dropped", to_integer(s_pdelay_s), 0, failure);

    -- A new master takes over
    rx_send(ptp_message(ptp_msg_sync_c, 7, master2_id_c, timestamp_zero_c,
                        two_step => true),
            t2g_c);
    wait for 1 us;
    assert_equal("relock", s_locked_s, '1', failure);
    rx_send(ptp_message(ptp_msg_follow_up_c, 7, master2_id_c, t1g_c), t2g_c);
    offset_expect("relocked sync", 6, 2500, 0);

    log_info("PTP slave OK");
    done_s(0) <= '1';
    wait;
  end process;

  -- Scripted master: bench slave
  ----------------------------------------------------------------

  master_tx_mon: process is
    variable beat_v: master_t;
    variable buf_v: byte_string(0 to 63);
    variable n_v: natural;
  begin
    m_tx_s.s <= accept(cfg_c, false);
    m_strobe_s <= '0';
    m_txcap_s <= decoy_ts_c;
    wait for 100 ns;

    loop
      n_v := 0;
      buf_v := (others => x"00");
      loop
        receive(cfg_c, clock_s, m_tx_s.m, m_tx_s.s, beat_v);
        buf_v(n_v) := beat_v.data(0);
        n_v := n_v + 1;
        exit when is_last(cfg_c, beat_v);
      end loop;

      m_txbuf_s <= buf_v;
      m_txlen_s <= n_v;
      m_txcnt_s <= m_txcnt_s + 1;

      if tag_strobes(buf_v(0)) then
        -- The capture register is written first, the done strobe
        -- follows.  The value is only presented for the strobe cycle,
        -- so a follow up sending the capture file's current contents
        -- rather than the latched time cannot pass unnoticed.
        m_txcap_s <= m_t1_s;
        wait until rising_edge(clock_s);
        m_strobe_s <= '1';
        wait until rising_edge(clock_s);
        m_strobe_s <= '0';
        m_txcap_s <= decoy_ts_c;
      end if;
    end loop;
  end process;

  master_script: process is
    constant t1a_c : timestamp_t := ts_of(base_sec_c, 42000);
    constant t1b_c : timestamp_t := ts_of(base_sec_c, 4242000);
    constant t4a_c : timestamp_t := ts_of(base_sec_c, 777000);

    variable txn_v: natural := 0;
    variable seq_v: natural;

    procedure tx_get is
    begin
      if m_txcnt_s = txn_v then
        wait until m_txcnt_s /= txn_v;
      end if;
      txn_v := m_txcnt_s;
      wait until rising_edge(clock_s);
    end procedure;

    impure function pb(k: integer) return byte is
    begin
      return m_txbuf_s(hdr_size_c + k);
    end function;

    impure function ps(f, l: integer) return byte_string is
    begin
      return m_txbuf_s(hdr_size_c + f to hdr_size_c + l);
    end function;

    procedure check_common(constant what: string;
                           constant msg_type: natural;
                           constant length: natural) is
    begin
      assert_equal(what & " total length", m_txlen_s, hdr_size_c + length,
                   failure);
      assert_equal(what & " peer",
                   m_txbuf_s(tag_length_c to tag_length_c+5),
                   ptp_multicast_addr_c, failure);
      assert_equal(what & " casting", m_txbuf_s(tag_length_c+6),
                   l2_multicast(master_group_c), failure);
      assert_equal(what & " type", pb(ptp_off_type_c), to_byte(msg_type),
                   failure);
      assert_equal(what & " version", pb(ptp_off_version_c), to_byte(2),
                   failure);
      assert_equal(what & " length field",
                   to_integer(from_be(ps(ptp_off_length_c,
                                         ptp_off_length_c+1))),
                   length, failure);
      assert_equal(what & " domain", pb(ptp_off_domain_c), to_byte(0),
                   failure);
      assert_equal(what & " source",
                   ps(ptp_off_source_port_identity_c,
                      ptp_off_source_port_identity_c+9),
                   port_identity(master_clock_c), failure);
    end procedure;
  begin
    m_rx_s.m <= transfer_defaults(cfg_c);
    m_t1_s <= t1a_c;
    wait for 100 ns;

    tx_get;
    check_common("sync", ptp_msg_sync_c, ptp_sync_length_c);
    assert tag_strobes(m_txbuf_s(0))
      report "Sync must request the transmit strobe"
      severity failure;
    assert_equal("sync tag id", tag_id(m_txbuf_s(0)), ptp_tx_tag_id_c,
                 failure);
    assert m_txbuf_s(hdr_size_c + ptp_off_flags_c)(ptp_flag0_two_step_c) = '1'
      report "Sync must carry the two step flag"
      severity failure;
    assert_equal("sync control", pb(ptp_off_control_c), to_byte(0), failure);
    seq_v := to_integer(from_be(ps(ptp_off_sequence_id_c,
                                   ptp_off_sequence_id_c+1)));

    tx_get;
    check_common("follow up", ptp_msg_follow_up_c, ptp_follow_up_length_c);
    assert not tag_strobes(m_txbuf_s(0))
      report "Follow_Up must not request the transmit strobe"
      severity failure;
    assert_equal("follow up control", pb(ptp_off_control_c), to_byte(2),
                 failure);
    assert_equal("follow up sequence",
                 to_integer(from_be(ps(ptp_off_sequence_id_c,
                                       ptp_off_sequence_id_c+1))),
                 seq_v, failure);
    assert_equal("follow up origin timestamp",
                 ps(ptp_off_timestamp_c, ptp_off_timestamp_c+9),
                 to_ptp_timestamp(t1a_c), failure);

    -- A delay request is answered with the captured receive time
    m_cap_s <= t4a_c;
    wait until rising_edge(clock_s);
    packet_send(cfg_c, clock_s, m_rx_s.s, m_rx_s.m,
                packet => rx_prefix_c
                          & ptp_message(ptp_msg_delay_req_c, 4242,
                                        port_identity(slave_clock_c),
                                        timestamp_zero_c),
                user => "0");

    tx_get;
    check_common("delay response", ptp_msg_delay_resp_c,
                 ptp_delay_resp_length_c);
    assert not tag_strobes(m_txbuf_s(0))
      report "Delay_Resp must not request the transmit strobe"
      severity failure;
    assert_equal("delay response control", pb(ptp_off_control_c), to_byte(3),
                 failure);
    assert_equal("delay response sequence",
                 to_integer(from_be(ps(ptp_off_sequence_id_c,
                                       ptp_off_sequence_id_c+1))),
                 4242, failure);
    assert_equal("delay response receive timestamp",
                 ps(ptp_off_timestamp_c, ptp_off_timestamp_c+9),
                 to_ptp_timestamp(t4a_c), failure);
    assert_equal("delay response requester",
                 ps(ptp_off_requesting_port_identity_c,
                    ptp_off_requesting_port_identity_c+9),
                 port_identity(slave_clock_c), failure);

    -- Next period, with a fresh origin timestamp
    m_t1_s <= t1b_c;
    tx_get;
    check_common("sync 2", ptp_msg_sync_c, ptp_sync_length_c);
    assert_equal("sync 2 sequence",
                 to_integer(from_be(ps(ptp_off_sequence_id_c,
                                       ptp_off_sequence_id_c+1))),
                 seq_v + 1, failure);

    tx_get;
    check_common("follow up 2", ptp_msg_follow_up_c, ptp_follow_up_length_c);
    assert_equal("follow up 2 sequence",
                 to_integer(from_be(ps(ptp_off_sequence_id_c,
                                       ptp_off_sequence_id_c+1))),
                 seq_v + 1, failure);
    assert_equal("follow up 2 origin timestamp",
                 ps(ptp_off_timestamp_c, ptp_off_timestamp_c+9),
                 to_ptp_timestamp(t1b_c), failure);

    log_info("PTP master OK");
    done_s(1) <= '1';
    wait;
  end process;

  -- Back to back pair over a constant delay wire, slave clock skewed
  ----------------------------------------------------------------

  -- Capture files: a frame whose contents start on the wire at bench
  -- time t has its SFD seen by the peer at t + bb_delay_c.  The value
  -- must be right on the cycle the tag byte enters the engine, so it
  -- is presented one half period ahead.
  bb_capture: process(clock_s) is
  begin
    if falling_edge(clock_s) then
      bb_mcap_s <= ts_of_ns(ns_at(now) + half_ns_c + bb_delay_c);
      bb_scap_s <= ts_of_ns(ns_at(now) + half_ns_c + bb_delay_c + bb_skew_c);
    end if;
  end process;

  bb_slave_strobe: process is
    variable started_v: boolean := false;
    variable strobes_v: boolean := false;
    variable start_v: integer := 0;
  begin
    wait until rising_edge(clock_s);

    if is_valid(cfg_c, bb_s2m_s.m) and is_ready(cfg_c, bb_s2m_s.s) then
      if not started_v then
        started_v := true;
        strobes_v := tag_strobes(bb_s2m_s.m.data(0));
        start_v := ns_at(now);
      end if;

      if is_last(cfg_c, bb_s2m_s.m) then
        started_v := false;
        if strobes_v then
          -- Capture register written, then the done strobe: both
          -- reach the engine on the same cycle, the value first.
          bb_stxcap_s <= ts_of_ns(start_v + bb_skew_c);
          bb_sstrobe_s <= '1';
          wait until rising_edge(clock_s);
          bb_sstrobe_s <= '0';
        end if;
      end if;
    end if;
  end process;

  bb_master_strobe: process is
    variable started_v: boolean := false;
    variable strobes_v: boolean := false;
    variable start_v: integer := 0;
  begin
    wait until rising_edge(clock_s);

    if is_valid(cfg_c, bb_m2s_s.m) and is_ready(cfg_c, bb_m2s_s.s) then
      if not started_v then
        started_v := true;
        strobes_v := tag_strobes(bb_m2s_s.m.data(0));
        start_v := ns_at(now);
      end if;

      if is_last(cfg_c, bb_m2s_s.m) then
        started_v := false;
        if strobes_v then
          bb_mtxcap_s <= ts_of_ns(start_v);
          bb_mstrobe_s <= '1';
          wait until rising_edge(clock_s);
          bb_mstrobe_s <= '0';
        end if;
      end if;
    end if;
  end process;

  bb_latch: process(clock_s) is
  begin
    if rising_edge(clock_s) then
      if bb_offset_valid_s = '1' then
        bb_off_last_s <= bb_offset_s;
        bb_off_cnt_s <= bb_off_cnt_s + 1;
      end if;
    end if;
  end process;

  bb_script: process is
  begin
    wait for 200 us;

    assert_equal("pair locked", bb_locked_s, '1', failure);
    assert bb_off_cnt_s >= 3
      report "Pair must have produced several measurements"
      severity failure;
    assert_equal("pair path delay", to_integer(bb_pdelay_s), bb_delay_c,
                 failure);
    assert_equal("pair offset", to_integer(bb_off_last_s), bb_skew_c, failure);
    assert_equal("pair never stepped", bb_step_valid_s, '0', failure);

    log_info("PTP pair OK");
    done_s(2) <= '1';
    wait;
  end process;

  watchdog: process is
  begin
    wait for 400 us;
    assert false
      report "Simulation did not complete in time"
      severity failure;
    wait;
  end process;

  slave_dut: nsl_ptp.stream_l2.ptp_l2_slave
    generic map(
      config_c => cfg_c,
      header_length_c => hdr_c,
      clock_i_hz_c => engine_hz_c,
      delay_req_period_c => 2,
      sync_timeout_c => 4,
      multicast_group_c => slave_group_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      clock_identity_i => slave_clock_c,

      capture_time_i => s_cap_s,

      tx_strobe_i => s_strobe_s,
      tx_capture_time_i => s_txcap_s,

      rx_i => s_rx_s.m,
      rx_o => s_rx_s.s,
      tx_o => s_tx_s.m,
      tx_i => s_tx_s.s,

      offset_o => s_offset_s,
      offset_valid_o => s_offset_valid_s,
      step_o => s_step_s,
      step_sync_o => s_step_sync_s,
      step_valid_o => s_step_valid_s,
      path_delay_o => s_pdelay_s,
      locked_o => s_locked_s
      );

  master_dut: nsl_ptp.stream_l2.ptp_l2_master
    generic map(
      config_c => cfg_c,
      header_length_c => hdr_c,
      clock_i_hz_c => engine_hz_c,
      sync_period_c => 2,
      multicast_group_c => master_group_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      clock_identity_i => master_clock_c,

      capture_time_i => m_cap_s,

      tx_strobe_i => m_strobe_s,
      tx_capture_time_i => m_txcap_s,

      rx_i => m_rx_s.m,
      rx_o => m_rx_s.s,
      tx_o => m_tx_s.m,
      tx_i => m_tx_s.s
      );

  bb_slave: nsl_ptp.stream_l2.ptp_l2_slave
    generic map(
      config_c => cfg_c,
      header_length_c => hdr_c,
      clock_i_hz_c => engine_hz_c,
      delay_req_period_c => 1,
      sync_timeout_c => 4,
      multicast_group_c => slave_group_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      clock_identity_i => slave_clock_c,

      capture_time_i => bb_scap_s,

      tx_strobe_i => bb_sstrobe_s,
      tx_capture_time_i => bb_stxcap_s,

      rx_i => bb_m2s_s.m,
      rx_o => bb_m2s_s.s,
      tx_o => bb_s2m_s.m,
      tx_i => bb_s2m_s.s,

      offset_o => bb_offset_s,
      offset_valid_o => bb_offset_valid_s,
      step_o => bb_step_s,
      step_sync_o => bb_step_sync_s,
      step_valid_o => bb_step_valid_s,
      path_delay_o => bb_pdelay_s,
      locked_o => bb_locked_s
      );

  bb_master: nsl_ptp.stream_l2.ptp_l2_master
    generic map(
      config_c => cfg_c,
      header_length_c => hdr_c,
      clock_i_hz_c => engine_hz_c,
      sync_period_c => 1,
      multicast_group_c => slave_group_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      clock_identity_i => master_clock_c,

      capture_time_i => bb_mcap_s,

      tx_strobe_i => bb_mstrobe_s,
      tx_capture_time_i => bb_mtxcap_s,

      rx_i => bb_s2m_s.m,
      rx_o => bb_s2m_s.s,
      tx_o => bb_m2s_s.m,
      tx_i => bb_m2s_s.s
      );

  simdrv: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => clock_period_c,
      reset_duration => (others => 32 ns),
      clock_o(0) => clock_s,
      reset_n_o(0) => reset_n_s,
      done_i => done_s
      );

end;
