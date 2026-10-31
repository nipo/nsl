library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_simulation, nsl_transceiver, nsl_cuff, nsl_io, nsl_amba,
  nsl_line_coding, nsl_math, nsl_data;
use nsl_data.bytestream.all;
use nsl_math.int_ext.all;
use nsl_transceiver.lane.all;
use nsl_cuff.protocol.all;
use nsl_cuff.link.all;
use nsl_simulation.logging.all;

-- A complete CUFF link over two modelled transceiver quads, one per
-- end, cabled to each other with a propagation delay that is not a
-- whole number of bit periods.
--
-- CUFF's own transceiver recovers the stream with an IO delay line
-- and owns the 8b/10b codec, the bit alignment and the bit slip. A
-- quad owns all three instead, so the adapter has to hand the link
-- layer a stream framed by someone else, and the link layer's
-- alignment handshake has to be satisfied by the quad's comma
-- search. Nothing exercised that.
--
-- The link is also cut and restored while it is carrying data, which
-- is the one thing a link layer exists for: a quad whose alignment
-- never dropped, or never came back, would pass a test that only
-- brought the link up once.
entity tb is
end tb;

architecture arch of tb is

  constant endpoint_count_c : natural := 2;
  constant mtu_l2_c : natural range 0 to 15 := 6;

  -- Cable delay. Deliberately not a whole number of the 800 ps bit
  -- period, so the receiver has to find the bit centre rather than
  -- inherit it.
  constant propagation_c : time := 2600 ps;

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 0);

  -- CUFF frames its lane with K28.7, the singular comma, and carries
  -- no rate-matching sequence: the link is synchronous, so a quad
  -- that had to insert or drop a word would corrupt it. Leaving the
  -- sequence out makes the model say so instead.
  constant sync_c : nsl_transceiver.lane.sync_t := (
    comma_value => (0 => nsl_line_coding.ibm_8b10b.K28_7.data,
                    others => x"00"),
    comma_mask => (0 => x"ff", others => x"00"),
    comma_byte_count => 1,
    comma_negated => false,
    clock_correction_pattern => (others => x"00"),
    clock_correction_byte_count => 0,
    idle_pattern => (others => x"00"),
    idle_byte_count => 0
    );

  constant config_c : nsl_transceiver.cluster.config_t
    := nsl_transceiver.cluster.config(
      plls => (0 => (enabled => true,
                     ref_clock_index => 0,
                     ref_clock_mhz => 125,
                     target_vco_mhz => 2500)),
      refclks => (0 => (ref_clock_index => 0, ref_clock_mhz => 125),
                  1 => (ref_clock_index => 1, ref_clock_mhz => 125)),
      lanes => (0 => nsl_transceiver.lane.config(
        data_byte_count => 1,
        encoding => ENCODING_8B10B,
        line_rate_mbps => 1250,
        pll_index => 0,
        ref_clock_index => 0,
        user_clock_group_index => 0,
        sync => sync_c)),
      user_clock_group_count => 1
      );

  constant ref_clock_c : integer_vector(0 to 1)
    := (nsl_transceiver.target.clock_id("ref0"),
        nsl_transceiver.target.clock_id("stableclk"));

  type link_state_vector is array (natural range <>) of link_state_t;

  signal tx_pad_s, rx_pad_s
    : nsl_io.diff.diff_pair_vector(0 to endpoint_count_c-1);
  signal line_s : std_ulogic_vector(0 to endpoint_count_c-1);

  signal lane_clock_s, lane_rx_clock_s
    : std_ulogic_vector(0 to endpoint_count_c-1);

  signal tx_m_s : nsl_transceiver.lane.tx_master_vector(0 to endpoint_count_c-1);
  signal tx_s_s : nsl_transceiver.lane.tx_slave_vector(0 to endpoint_count_c-1);
  signal rx_m_s : nsl_transceiver.lane.rx_master_vector(0 to endpoint_count_c-1);
  signal rx_s_s : nsl_transceiver.lane.rx_slave_vector(0 to endpoint_count_c-1);

  signal tx_lane_s, rx_lane_s : cuff_code_vector(0 to endpoint_count_c-1);
  signal tx_data_s, rx_data_s : cuff_data_vector(0 to endpoint_count_c-1);
  signal state_s : link_state_vector(0 to endpoint_count_c-1);

  signal apb_clock_s : std_ulogic_vector(0 to endpoint_count_c-1);
  signal apb_s_s : nsl_amba.apb.slave_vector(0 to endpoint_count_c-1);

  -- Stimulus and scoreboard, shared between the sequencer and the
  -- checker below.
  -- The quad's comma search is this link's bit alignment, so its
  -- result is what the link layer waits on.
  signal align_ready_s : std_ulogic_vector(0 to endpoint_count_c-1);

  signal sending_s : std_ulogic;
  signal cut_s : std_ulogic;
  signal received_s : natural;

begin

  -- The cable. A cut is a line that stops moving, which is what the
  -- far end sees when a connector is pulled.
  cable: for e in 0 to endpoint_count_c-1 generate
    line_s(e) <= '0' when cut_s = '1'
                 else nsl_io.diff.to_se(tx_pad_s(endpoint_count_c-1-e));
    rx_pad_s(e) <= transport nsl_io.diff.to_diff(line_s(e)) after propagation_c;
  end generate;

  endpoints: for e in 0 to endpoint_count_c-1 generate
  begin

    align_ready_s(e) <= rx_m_s(e).pcs_aligned;

    quad: nsl_transceiver.cluster.transceiver_cluster
      generic map(
        config_c => config_c,
        ref_clock_c => ref_clock_c
        )
      port map(
        reset_n_i => reset_n_s,

        ref_clock_i(0) => clock_s,
        ref_clock_i(1) => clock_s,

        lane_tx_o => tx_pad_s(e to e),
        lane_rx_i => rx_pad_s(e to e),

        lane_tx_clock_o => lane_clock_s(e to e),
        lane_rx_clock_o => lane_rx_clock_s(e to e),

        tx_m_i => tx_m_s(e to e),
        tx_s_o => tx_s_s(e to e),
        rx_m_o => rx_m_s(e to e),
        rx_s_i => rx_s_s(e to e),

        pma_reset_n_i => (0 => '1'),

        apb_clock_o => apb_clock_s(e),
        apb_reset_n_i => reset_n_s,
        apb_m_i => nsl_amba.apb.transfer_idle(nsl_transceiver.cluster.csr_config_c),
        apb_s_o => apb_s_s(e)
        );

    adapter: nsl_transceiver.cuff.cuff_adapter
      generic map(
        lane_count_c => 1
        )
      port map(
        clock_i => lane_clock_s(e),
        reset_n_i => reset_n_s,

        tx_lane_i => tx_lane_s(e to e),
        rx_lane_o => rx_lane_s(e to e),

        tx_m_o => tx_m_s(e to e),
        tx_s_i => tx_s_s(e to e),
        rx_m_i => rx_m_s(e to e),
        rx_s_o => rx_s_s(e to e)
        );

    transmitter: nsl_cuff.link.link_transmitter
      generic map(
        lane_count_c => 1,
        mtu_l2_c => mtu_l2_c
        )
      port map(
        clock_i => lane_clock_s(e),
        reset_n_i => reset_n_s,

        data_i => tx_data_s(e to e),
        lane_o => tx_lane_s(e to e),
        -- An end advertises what its own receiver has reached, which
        -- is how the two sides walk up the sequence together.
        state_i => state_s(e)
        );

    receiver: nsl_cuff.link.link_receiver
      generic map(
        lane_count_c => 1,
        mtu_l2_c => mtu_l2_c
        )
      port map(
        clock_i => lane_clock_s(e),
        reset_n_i => reset_n_s,

        lane_i => rx_lane_s(e to e),
        align_restart_o => open,
        align_valid_o => open,
        align_ready_i => align_ready_s(e to e),

        data_o => rx_data_s(e to e),

        state_o => state_s(e)
        );

  end generate;

  -- End 1 only ever sends idles: one direction carrying data is
  -- enough to tell a stream apart from a link that merely came up,
  -- and both directions have to work for either end to leave the
  -- alignment sequence at all.
  tx_data_s(1) <= cuff_data_idle_c;

  feed: process
    variable count_v : byte;
  begin
    tx_data_s(0) <= cuff_data_idle_c;
    count_v := x"00";

    loop
      wait until rising_edge(lane_clock_s(0));

      if sending_s = '1' then
        tx_data_s(0) <= (data => count_v, control => CUFF_DATA);
        count_v := std_ulogic_vector(unsigned(count_v) + 1);
      else
        tx_data_s(0) <= cuff_data_idle_c;
        count_v := x"00";
      end if;
    end loop;
  end process;

  -- Every data word the far end hands up has to be the successor of
  -- the one before it. The link may be silent for a while, and a cut
  -- restarts the count, so the first word of a run is taken as given
  -- and the ones after it are not.
  --
  -- A lane with no word this cycle leaves its last one on the bus,
  -- which is what a registered output does, and the CUFF side has no
  -- way to express a gap: the word is simply re-encoded. So a cycle
  -- the lane did not fill ends the run rather than extending it.
  checker: process
    variable expect_v : byte;
    variable running_v : boolean;
    variable count_v : natural;
  begin
    received_s <= 0;
    running_v := false;
    count_v := 0;

    loop
      wait until rising_edge(lane_clock_s(1));

      if rx_data_s(1).control = CUFF_DATA and rx_m_s(1).valid = '1' then
        if running_v then
          assert rx_data_s(1).data = expect_v
            report "the link handed up "
            & integer'image(to_integer(unsigned(rx_data_s(1).data)))
            & " where " & integer'image(to_integer(unsigned(expect_v)))
            & " was next in the stream"
            severity failure;
        end if;

        expect_v := std_ulogic_vector(unsigned(rx_data_s(1).data) + 1);
        running_v := true;
        count_v := count_v + 1;
        received_s <= count_v;
      else
        running_v := false;
      end if;
    end loop;
  end process;

  sequencer: process
    constant ctxt : log_context := "cuff over a quad";

    -- Waits for both ends to agree on a state, or fails saying where
    -- each of them got stuck.
    procedure wait_state(target : link_state_t;
                         budget : natural;
                         what : string) is
      variable cycles_v : natural;
    begin
      cycles_v := 0;
      while state_s(0) /= target or state_s(1) /= target loop
        wait until rising_edge(lane_clock_s(0));
        cycles_v := cycles_v + 1;
        assert cycles_v < budget
          report what & ": end 0 is in " & link_state_t'image(state_s(0))
          & " and end 1 in " & link_state_t'image(state_s(1))
          & ", with lane alignment "
          & std_ulogic'image(rx_m_s(0).pcs_aligned) & " / "
          & std_ulogic'image(rx_m_s(1).pcs_aligned)
          severity failure;
      end loop;

      log_info(ctxt, what & " took " & integer'image(cycles_v) & " cycles");
    end procedure;

    procedure wait_not_running(budget : natural) is
      variable cycles_v : natural;
    begin
      cycles_v := 0;
      while state_s(0) = LINK_RUNNING or state_s(1) = LINK_RUNNING loop
        wait until rising_edge(lane_clock_s(0));
        cycles_v := cycles_v + 1;
        assert cycles_v < budget
          report "the link stayed up with its cable cut: end 0 in "
          & link_state_t'image(state_s(0)) & ", end 1 in "
          & link_state_t'image(state_s(1)) & ", lane alignment "
          & std_ulogic'image(rx_m_s(0).pcs_aligned) & " / "
          & std_ulogic'image(rx_m_s(1).pcs_aligned)
          severity failure;
      end loop;

      log_info(ctxt, "the link noticed the cut in "
               & integer'image(cycles_v) & " cycles");
    end procedure;

    -- Lets the stream run and reports how much of it arrived.
    procedure carry(word_count : natural; what : string) is
      variable before_v : natural;
    begin
      before_v := received_s;
      sending_s <= '1';

      for i in 0 to word_count-1 loop
        wait until rising_edge(lane_clock_s(0));
      end loop;

      sending_s <= '0';

      -- Let what is still in the lane's pipeline and its elastic
      -- buffer come out before counting.
      for i in 0 to 63 loop
        wait until rising_edge(lane_clock_s(0));
      end loop;

      -- One word in, one word out: the lane is not allowed to lose
      -- any of them. The last word may still be in flight.
      assert received_s >= before_v + word_count - 1
        report what & ": only "
        & integer'image(received_s - before_v) & " of "
        & integer'image(word_count) & " words came out the far end"
        severity failure;

      log_info(ctxt, what & ": " & integer'image(received_s - before_v)
               & " of " & integer'image(word_count) & " words arrived");
    end procedure;
  begin
    done_s(0) <= '0';
    sending_s <= '0';
    cut_s <= '0';

    wait until reset_n_s = '1';

    wait_state(LINK_RUNNING, 8192, "bringing the link up");

    carry(256, "with the cable connected");

    cut_s <= '1';
    wait_not_running(2048);

    cut_s <= '0';
    wait_state(LINK_RUNNING, 8192, "bringing the link back up");

    carry(256, "after the cable came back");

    done_s(0) <= '1';
    wait;
  end process;

  driver: nsl_simulation.driver.simulation_driver
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
