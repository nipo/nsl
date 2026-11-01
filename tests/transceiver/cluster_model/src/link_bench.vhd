library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_transceiver, nsl_io, nsl_amba, nsl_data, nsl_math, nsl_line_coding, nsl_simulation;
use nsl_data.bytestream.all;
use nsl_math.int_ext.all;
use nsl_transceiver.lane.all;
use nsl_simulation.logging.all;

-- Two lanes of one behaviourally modelled quad, wired to each other
-- at the pads, carrying a framed byte stream the receiving lane has
-- to recover.
--
-- The lanes come up from nothing: the model holds them in reset
-- until the PLL locks, hunts for the comma in a stream it has no
-- prior phase knowledge of, fills its elastic buffer, and only then
-- presents words. The frame marker is a control symbol the check
-- process hunts for, so nothing here depends on knowing the lane's
-- latency: a stream that came back in the wrong order, lost a byte,
-- or lost its K flag fails whatever the latency turns out to be.
--
-- The two lanes may be configured at different line rates, which is
-- how the elastic buffer is made to work: the receiving lane's own
-- clock then runs away from the stream arriving at it, and the only
-- thing standing between that and a corrupted frame is the
-- clock-correction sequence in the gaps.
entity link_bench is
  generic(
    data_byte_count_c : natural;
    line_rate_mbps_c : natural;
    -- Rate the receiving lane is configured for. Zero means the same
    -- as the transmitting one, which is the case with nothing for
    -- the elastic buffer to absorb.
    rx_rate_mbps_c : natural := 0;
    -- A pair wired the wrong way round, undone by the receiving
    -- lane's own polarity setting.
    polarity_invert_c : boolean := false;
    -- Whether the elastic buffer is expected to correct. With both
    -- lanes on the same rate it must not: a correction then means
    -- the buffer moved on its own and the stream lost or gained a
    -- word.
    expect_correction_c : boolean := false;
    frame_count_c : natural := 4;
    label_c : string
    );
  port(
    -- Reference clock, at the rate the configuration below names.
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;
    done_o : out std_ulogic
    );
end entity;

architecture beh of link_bench is

  -- 1000BASE-X framing, which is what every 8b/10b lane in the
  -- library uses: align on /K28.5/, rate-match on the /K28.5/D16.2/
  -- ordered set, and idle with the same set.
  constant comma_c : byte := nsl_line_coding.ibm_8b10b.K28_5.data;
  constant d16_2_c : byte := nsl_line_coding.ibm_8b10b.data(16, 2).data;

  constant sync_c : nsl_transceiver.lane.sync_t := (
    comma_value => (0 => comma_c, others => x"00"),
    comma_mask => (0 => x"ff", others => x"00"),
    comma_byte_count => 1,
    comma_negated => false,
    clock_correction_pattern => (0 => comma_c, 1 => d16_2_c, others => x"00"),
    clock_correction_byte_count => 2,
    idle_pattern => (0 => comma_c, 1 => d16_2_c, others => x"00"),
    idle_byte_count => 2
    );

  function rx_rate return natural
  is
  begin
    if rx_rate_mbps_c = 0 then
      return line_rate_mbps_c;
    end if;
    return rx_rate_mbps_c;
  end function;

  function lane_config(rate : natural; invert_rx : boolean)
    return nsl_transceiver.lane.config_t
  is
  begin
    return nsl_transceiver.lane.config(
      data_byte_count => data_byte_count_c,
      encoding => ENCODING_8B10B,
      line_rate_mbps => rate,
      pll_index => 0,
      ref_clock_index => 0,
      user_clock_group_index => 0,
      polarity_invert_tx => polarity_invert_c and not invert_rx,
      polarity_invert_rx => polarity_invert_c and invert_rx,
      sync => sync_c);
  end function;

  constant config_c : nsl_transceiver.cluster.config_t
    := nsl_transceiver.cluster.config(
      plls => (0 => (enabled => true,
                     ref_clock_index => 0,
                     ref_clock_mhz => 125,
                     target_vco_mhz => 2500)),
      refclks => (0 => (ref_clock_index => 0, ref_clock_mhz => 125),
                  1 => (ref_clock_index => 1, ref_clock_mhz => 125)),
      lanes => (0 => lane_config(line_rate_mbps_c, false),
                1 => lane_config(rx_rate, true)),
      user_clock_group_count => 1
      );

  -- The housekeeping clock is the second entry, so the model has
  -- somewhere to clock the configuration bus from.
  constant ref_clock_c : integer_vector(0 to 1)
    := (nsl_transceiver.target.clock_id("ref0"),
        nsl_transceiver.target.clock_id("stableclk"));

  -- One control symbol opens each frame and the rest counts, so a
  -- frame starting on the wrong byte, or short one, is visible
  -- without knowing where in the stream we joined.
  constant frame_byte_count_c : natural := 32;
  constant marker_c : byte := nsl_line_coding.ibm_8b10b.K27_7.data;

  -- Words the transmitter stops presenting between frames. The
  -- model fills them with its idle pattern, which is also the
  -- rate-matching sequence, so this is the room the elastic buffer
  -- has to work in.
  constant gap_word_count_c : natural
    := 32 / data_byte_count_c;

  signal pad_s : nsl_io.diff.diff_pair_vector(0 to 1);
  signal lane_clock_s, lane_rx_clock_s : std_ulogic_vector(0 to 1);

  signal tx_m_s : nsl_transceiver.lane.tx_master_vector(0 to 1);
  signal tx_s_s : nsl_transceiver.lane.tx_slave_vector(0 to 1);
  signal rx_m_s : nsl_transceiver.lane.rx_master_vector(0 to 1);
  signal rx_s_s : nsl_transceiver.lane.rx_slave_vector(0 to 1);

  signal apb_clock_s : std_ulogic;
  signal apb_s_s : nsl_amba.apb.slave_t;

begin

  dut: nsl_transceiver.cluster.transceiver_cluster
    generic map(
      config_c => config_c,
      ref_clock_c => ref_clock_c
      )
    port map(
      reset_n_i => reset_n_i,

      ref_clock_i(0) => clock_i,
      ref_clock_i(1) => clock_i,

      lane_tx_o => pad_s,
      -- Each lane listens to the other, which is the shortest
      -- two-ended link a quad can carry.
      lane_rx_i(0) => pad_s(1),
      lane_rx_i(1) => pad_s(0),

      lane_tx_clock_o => lane_clock_s,
      lane_rx_clock_o => lane_rx_clock_s,

      tx_m_i => tx_m_s,
      tx_s_o => tx_s_s,
      rx_m_o => rx_m_s,
      rx_s_i => rx_s_s,

      pma_reset_n_i => (others => '1'),

      apb_clock_o => apb_clock_s,
      apb_reset_n_i => reset_n_i,
      apb_m_i => nsl_amba.apb.transfer_idle(nsl_transceiver.cluster.csr_config_c),
      apb_s_o => apb_s_s
      );

  -- Nothing here reconfigures a lane at runtime, and the adapter
  -- side of the contract is driven from the two processes below.
  rx_s_s <= (others => (ready => '1',
                        pcs_reset_n => '1',
                        align_trigger => '0',
                        chbond_start => '0',
                        control => (others => '0'),
                        prbs_select => PRBS_NONE,
                        prbs_error_reset => '0'));

  -- The receiving lane has nothing of its own to send, so it sends
  -- the model's idle pattern. That is what keeps the transmitting
  -- lane's own receiver aligned, which both lanes need before
  -- either reports a word.
  tx_m_s(1) <= (
    data => (others => (others => '-')),
    aux => (others => (others => '-')),
    valid => '0',
    pcs_reset_n => '1',
    control => (others => '0'),
    control_h => (others => '0'),
    c2i_clock => '0',
    prbs_select => PRBS_NONE,
    prbs_force_error => '0'
    );

  feed: process
    variable phase_v : natural;
    variable gap_v : natural;
    variable byte_v : byte;
  begin
    tx_m_s(0) <= nsl_transceiver.lane.null_tx_master_c;
    tx_m_s(0).valid <= '0';
    tx_m_s(0).pcs_reset_n <= '1';
    tx_m_s(0).control <= (others => '0');
    tx_m_s(0).control_h <= (others => '0');
    tx_m_s(0).c2i_clock <= '0';

    phase_v := 0;
    gap_v := 0;

    wait until reset_n_i = '1';

    loop
      wait until rising_edge(lane_clock_s(0));

      if gap_v /= 0 then
        -- The model substitutes its idle pattern here, which is
        -- what keeps the far end aligned between frames and what
        -- its elastic buffer is allowed to add to and take from.
        tx_m_s(0).valid <= '0';
        gap_v := gap_v - 1;
      else
        for i in 0 to data_byte_count_c-1 loop
          if phase_v = 0 then
            byte_v := marker_c;
            tx_m_s(0).aux(i) <= (0 => '1', others => '0');
          else
            byte_v := std_ulogic_vector(to_unsigned(phase_v, 8));
            tx_m_s(0).aux(i) <= (others => '0');
          end if;

          tx_m_s(0).data(i) <= byte_v;
          phase_v := (phase_v + 1) mod frame_byte_count_c;
        end loop;

        tx_m_s(0).valid <= '1';

        if phase_v = 0 then
          gap_v := gap_word_count_c;
        end if;
      end if;
    end loop;
  end process;

  check: process
    constant ctxt : log_context := label_c;
    -- Byte the frame owes next, or -1 while hunting for a marker.
    variable expect_v : integer;
    variable frames_v : natural;
    variable cycles_v : natural;
    variable settle_v : natural;
    variable corrections_v : natural;
    variable byte_v : byte;
  begin
    done_o <= '0';

    wait until reset_n_i = '1';

    -- The lane has to come up on its own: a PLL that locks, a comma
    -- the receiver finds in a stream it has no phase knowledge of,
    -- and an elastic buffer that fills before it presents anything.
    cycles_v := 0;
    while rx_m_s(1).pcs_aligned /= '1' or rx_m_s(1).valid /= '1' loop
      wait until rising_edge(lane_rx_clock_s(1));
      cycles_v := cycles_v + 1;
      assert cycles_v < 4096
        report "the lane never came up: pma lock "
        & std_ulogic'image(rx_m_s(1).pma_lock) & ", aligned "
        & std_ulogic'image(rx_m_s(1).pcs_aligned) & ", valid "
        & std_ulogic'image(rx_m_s(1).valid)
        severity failure;
    end loop;

    assert rx_m_s(1).pma_lock = '1'
      report "the lane presents words without having locked to the line"
      severity failure;

    assert rx_m_s(1).elec_idle = '0'
      report "the lane presents words while calling the line idle"
      severity failure;

    assert tx_s_s(0).ready = '1' and tx_s_s(0).pll_lock = '1'
      report "the lane receives but does not accept transmit words"
      severity failure;

    log_info(ctxt, "lane came up in " & integer'image(cycles_v)
             & " words after reset");

    -- The word the lane came up on may be the tail of a frame, so
    -- the first marker is the start of everything checked below.
    expect_v := -1;
    frames_v := 0;
    settle_v := 0;
    corrections_v := 0;

    while frames_v < frame_count_c loop
      wait until rising_edge(lane_rx_clock_s(1));

      settle_v := settle_v + 1;
      assert settle_v < 8192
        report "only " & integer'image(frames_v) & " of "
        & integer'image(frame_count_c) & " frames came back"
        severity failure;

      if rx_m_s(1).clock_corrected = '1' then
        corrections_v := corrections_v + 1;

        assert expect_correction_c
          report "the elastic buffer corrected a lane that has no rate"
          & " difference to correct for"
          severity failure;
      end if;

      next when rx_m_s(1).valid /= '1';

      for i in 0 to data_byte_count_c-1 loop
        byte_v := rx_m_s(1).data(i);

        assert rx_m_s(1).aux(i)(1) = '0'
          report "the receiver reports an invalid code group"
          severity failure;
        assert rx_m_s(1).aux(i)(2) = '0'
          report "the receiver reports a running disparity error"
          severity failure;

        if expect_v < 0 then
          if rx_m_s(1).aux(i)(0) = '1' and byte_v = marker_c then
            expect_v := 1;
          end if;
        else
          assert rx_m_s(1).aux(i)(0) = '0'
            report "byte " & integer'image(expect_v)
            & " of the frame came back flagged as a control symbol"
            severity failure;

          assert byte_v = std_ulogic_vector(to_unsigned(expect_v, 8))
            report "byte " & integer'image(expect_v)
            & " of the frame came back as "
            & integer'image(to_integer(unsigned(byte_v)))
            severity failure;

          expect_v := expect_v + 1;
          if expect_v = frame_byte_count_c then
            expect_v := -1;
            frames_v := frames_v + 1;
            settle_v := 0;
          end if;
        end if;
      end loop;
    end loop;

    -- A rate difference the buffer never had to correct for would
    -- mean the two lanes were not running at different rates after
    -- all, and the whole path this case exists for went unused.
    assert not expect_correction_c or corrections_v /= 0
      report "the lane carried the stream without the elastic buffer"
      & " ever correcting, so the rate difference never bit"
      severity failure;

    log_info(ctxt, "recovered " & integer'image(frame_count_c)
             & " frames of " & integer'image(frame_byte_count_c)
             & " bytes over a " & integer'image(line_rate_mbps_c)
             & " Mbps lane received at " & integer'image(rx_rate)
             & " Mbps, with " & integer'image(corrections_v)
             & " elastic buffer corrections");

    done_o <= '1';
    wait;
  end process;

end architecture;
