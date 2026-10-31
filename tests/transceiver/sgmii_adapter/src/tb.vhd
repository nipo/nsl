library ieee;
use ieee.std_logic_1164.all;

library nsl_simulation, nsl_transceiver, nsl_mii, nsl_bnoc, nsl_io, nsl_amba,
  nsl_line_coding, nsl_math, nsl_data;
use nsl_data.bytestream.all;
use nsl_data.text.all;
use nsl_math.int_ext.all;
use nsl_transceiver.lane.all;
use nsl_bnoc.committed.all;
use nsl_bnoc.testing.all;
use nsl_simulation.logging.all;

-- SGMII over a modelled transceiver quad: two lanes of one cluster,
-- wired to each other at the pads, each carrying a complete SGMII
-- end.
--
-- The serdes backend in nsl_mii recovers the symbol stream with an IO
-- delay line, so a lane behind a transceiver is a different path
-- entirely: the quad owns the 8b/10b codec, the comma alignment and
-- the elastic buffer, and the adapter has to hand the PCS what it
-- would have got from its own decoder. Nothing exercised that path
-- before. In particular the PCS drives the running disparity of
-- every group it emits and expects the line to follow it, which only
-- works if the adapter's disparity request reaches the encoder with
-- the polarity the PCS meant.
--
-- Both ends autonegotiate, so the frames below only move once the
-- lanes have aligned and the link timers have expired on both sides.
entity tb is
end tb;

architecture arch of tb is

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 3);

  constant frame_c : byte_string
    := from_hex("02000000feed00deadbeef0001020304050607");

  constant comma_c : byte := nsl_line_coding.ibm_8b10b.K28_5.data;
  constant d16_2_c : byte := nsl_line_coding.ibm_8b10b.data(16, 2).data;

  -- 1000BASE-X, which is what SGMII frames its lane as: align on
  -- /K28.5/, rate-match on the /K28.5/D16.2/ ordered set.
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

  constant lane_c : nsl_transceiver.lane.config_t
    := nsl_transceiver.lane.config(
      data_byte_count => 1,
      encoding => ENCODING_8B10B,
      line_rate_mbps => 1250,
      pll_index => 0,
      ref_clock_index => 0,
      user_clock_group_index => 0,
      sync => sync_c
      );

  constant config_c : nsl_transceiver.cluster.config_t
    := nsl_transceiver.cluster.config(
      plls => (0 => (enabled => true,
                     ref_clock_index => 0,
                     ref_clock_mhz => 125,
                     target_vco_mhz => 2500)),
      refclks => (0 => (ref_clock_index => 0, ref_clock_mhz => 125),
                  1 => (ref_clock_index => 1, ref_clock_mhz => 125)),
      lanes => (0 => lane_c, 1 => lane_c),
      user_clock_group_count => 1
      );

  constant ref_clock_c : integer_vector(0 to 1)
    := (nsl_transceiver.target.clock_id("ref0"),
        nsl_transceiver.target.clock_id("stableclk"));

  signal pad_s : nsl_io.diff.diff_pair_vector(0 to 1);
  signal lane_tx_clock_s, lane_rx_clock_s : std_ulogic_vector(0 to 1);

  signal tx_m_s : nsl_transceiver.lane.tx_master_vector(0 to 1);
  signal tx_s_s : nsl_transceiver.lane.tx_slave_vector(0 to 1);
  signal rx_m_s : nsl_transceiver.lane.rx_master_vector(0 to 1);
  signal rx_s_s : nsl_transceiver.lane.rx_slave_vector(0 to 1);

  signal sgmii_m2p_s : nsl_mii.sgmii.sgmii_m2p_vector(0 to 1);
  signal sgmii_p2m_s : nsl_mii.sgmii.sgmii_p2m_vector(0 to 1);

  signal link_up_s : std_ulogic_vector(0 to 1);

  signal tx_bus_s, rx_bus_s : nsl_bnoc.committed.committed_bus_vector(0 to 1);

  signal apb_clock_s : std_ulogic;
  signal apb_s_s : nsl_amba.apb.slave_t;

begin

  quad: nsl_transceiver.cluster.transceiver_cluster
    generic map(
      config_c => config_c,
      ref_clock_c => ref_clock_c
      )
    port map(
      reset_n_i => reset_n_s,

      ref_clock_i(0) => clock_s,
      ref_clock_i(1) => clock_s,

      lane_tx_o => pad_s,
      -- Lane 0 listens to lane 1 and the other way round, which is
      -- the shortest two-ended link a quad can carry.
      lane_rx_i(0) => pad_s(1),
      lane_rx_i(1) => pad_s(0),

      lane_tx_clock_o => lane_tx_clock_s,
      lane_rx_clock_o => lane_rx_clock_s,

      tx_m_i => tx_m_s,
      tx_s_o => tx_s_s,
      rx_m_o => rx_m_s,
      rx_s_i => rx_s_s,

      pma_reset_n_i => (others => '1'),

      apb_clock_o => apb_clock_s,
      apb_reset_n_i => reset_n_s,
      apb_m_i => nsl_amba.apb.transfer_idle(nsl_transceiver.cluster.csr_config_c),
      apb_s_o => apb_s_s
      );

  adapter: nsl_transceiver.sgmii.sgmii_adapter
    port map(
      sgmii_i => sgmii_m2p_s,
      sgmii_o => sgmii_p2m_s,

      tx_m_o => tx_m_s,
      tx_s_i => tx_s_s,
      rx_m_i => rx_m_s,
      rx_s_o => rx_s_s
      );

  ends: for i in 0 to 1 generate
  begin

    driver: nsl_mii.sgmii.sgmii_driver
      generic map(
        -- Faster simulation than the specified 1.6 ms.
        link_timer_c => 30
        )
      port map(
        reset_n_i => reset_n_s,
        -- The lane's own clock, which is what an adapter-side PCS
        -- has to run on: the quad recovers it.
        clock_i => lane_tx_clock_s(i),

        sgmii_o => sgmii_m2p_s(i),
        sgmii_i => sgmii_p2m_s(i),

        link_speed_i => nsl_mii.link.LINK_SPEED_1000,
        link_up_o => link_up_s(i),

        rx_o => rx_bus_s(i).req,
        rx_i => rx_bus_s(i).ack,

        tx_i => tx_bus_s(i).req,
        tx_o => tx_bus_s(i).ack
        );

  end generate;

  -- Nothing is sent before both ends agree the link is up, so a lane
  -- that never aligned fails as a timeout here rather than as a
  -- frame that went missing.
  link: process
    constant ctxt : log_context := "sgmii link";
    variable cycles_v : natural;
  begin
    done_s(0) <= '0';

    wait until reset_n_s = '1';

    cycles_v := 0;
    while link_up_s /= "11" loop
      wait until rising_edge(lane_tx_clock_s(0));
      cycles_v := cycles_v + 1;
      assert cycles_v < 8192
        report "the link never came up: lane 0 aligned "
        & std_ulogic'image(rx_m_s(0).pcs_aligned) & ", lane 1 aligned "
        & std_ulogic'image(rx_m_s(1).pcs_aligned) & ", link up "
        & std_ulogic'image(link_up_s(0)) & " / "
        & std_ulogic'image(link_up_s(1))
        severity failure;
    end loop;

    log_info(ctxt, "both ends autonegotiated in " & integer'image(cycles_v)
             & " cycles over the modelled quad");

    -- The PCS tracks the running disparity itself and tells the
    -- adapter which one to encode with. A line that did not follow
    -- it would report disparity errors here while still decoding
    -- every symbol, which is exactly the failure that makes an
    -- SGMII link come up and then drop frames.
    for i in 0 to 1 loop
      assert sgmii_p2m_s(i).code_err = '0'
        report "lane " & integer'image(i)
        & " reports an invalid code group on an idle link"
        severity failure;
      assert sgmii_p2m_s(i).disparity_err = '0'
        report "lane " & integer'image(i)
        & " reports a running disparity error on an idle link, so the"
        & " line is not following the disparity the PCS asked for"
        severity failure;
    end loop;

    log_info(ctxt, "the quad encoded every group with the disparity the"
             & " PCS asked for");

    done_s(0) <= '1';
    wait;
  end process;

  -- One frame each way: a lane that transmits but cannot receive
  -- would pass a single direction.
  send: process
  begin
    done_s(1) <= '0';

    wait until reset_n_s = '1';
    wait until link_up_s = "11";

    committed_put(tx_bus_s(0).req, tx_bus_s(0).ack,
                  lane_tx_clock_s(0), frame_c, true);
    committed_put(tx_bus_s(1).req, tx_bus_s(1).ack,
                  lane_tx_clock_s(1), frame_c, true);

    done_s(1) <= '1';
    wait;
  end process;

  -- The receiving ends listen from the start: a check that only
  -- begins once the frame has been handed to the far end would miss
  -- the part of it already in flight.
  recv: for i in 0 to 1 generate
  begin

    check: process
    begin
      done_s(2 + i) <= '0';

      committed_check("sgmii end " & integer'image(1 - i),
                      rx_bus_s(1 - i).req, rx_bus_s(1 - i).ack,
                      lane_tx_clock_s(1 - i), frame_c, true, LOG_LEVEL_FATAL);

      done_s(2 + i) <= '1';
      wait;
    end process;

  end generate;

  driver_i: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 8 ns,
      reset_duration(0) => 20 ns,
      reset_n_o(0) => reset_n_s,
      clock_o(0) => clock_s,
      done_i => done_s
      );

end;
