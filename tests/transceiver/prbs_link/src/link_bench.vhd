library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_transceiver, nsl_io, nsl_amba, nsl_data, nsl_math, nsl_simulation;
use nsl_data.bytestream.all;
use nsl_math.int_ext.all;
use nsl_transceiver.lane.all;
use nsl_simulation.logging.all;

-- Two lanes of one behaviourally modelled quad, configured for
-- ENCODING_PRBS and cabled to each other at the pads.
--
-- Nothing frames this link: there is no comma to align on and no
-- word boundary to find, so the whole path is the pattern generator,
-- the serialiser, the cable, the bit recovery, and a checker that has
-- to find the pattern's phase in the bits themselves. That is what
-- makes it the measurement a transceiver is brought up with: it
-- answers whether the line carries bits at all, before any protocol
-- is in a position to ask.
entity link_bench is
  generic(
    data_byte_count_c : natural;
    line_rate_mbps_c : natural;
    mode_c : prbs_mode_t;
    -- A pattern the receiving end is pointed at part way, which it
    -- must fail to find in a line carrying mode_c.
    other_mode_c : prbs_mode_t;
    label_c : string
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;
    done_o : out std_ulogic
    );
end entity;

architecture beh of link_bench is

  -- A cable length that is not a whole number of the bit period, so
  -- the receiver has to find the bit centre rather than inherit it.
  constant propagation_c : time := 2600 ps;

  function lane_config return nsl_transceiver.lane.config_t
  is
  begin
    return nsl_transceiver.lane.config(
      data_byte_count => data_byte_count_c,
      encoding => ENCODING_PRBS,
      line_rate_mbps => line_rate_mbps_c,
      pll_index => 0,
      ref_clock_index => 0,
      user_clock_group_index => 0);
  end function;

  constant config_c : nsl_transceiver.cluster.config_t
    := nsl_transceiver.cluster.config(
      plls => (0 => (enabled => true,
                     ref_clock_index => 0,
                     ref_clock_mhz => 125,
                     target_vco_mhz => 2500)),
      refclks => (0 => (ref_clock_index => 0, ref_clock_mhz => 125),
                  1 => (ref_clock_index => 1, ref_clock_mhz => 125)),
      lanes => (0 => lane_config, 1 => lane_config),
      user_clock_group_count => 1
      );

  constant ref_clock_c : integer_vector(0 to 1)
    := (nsl_transceiver.target.clock_id("ref0"),
        nsl_transceiver.target.clock_id("stableclk"));

  signal pad_s, rx_pad_s : nsl_io.diff.diff_pair_vector(0 to 1);
  signal lane_clock_s, lane_rx_clock_s : std_ulogic_vector(0 to 1);

  signal tx_m_s : nsl_transceiver.lane.tx_master_vector(0 to 1);
  signal tx_s_s : nsl_transceiver.lane.tx_slave_vector(0 to 1);
  signal rx_m_s : nsl_transceiver.lane.rx_master_vector(0 to 1);
  signal rx_s_s : nsl_transceiver.lane.rx_slave_vector(0 to 1);

  signal apb_clock_s : std_ulogic;
  signal apb_s_s : nsl_amba.apb.slave_t;

  signal tx_mode_s, rx_mode_s : prbs_mode_t;
  signal force_error_s, error_reset_s : std_ulogic;

begin

  cable: for e in 0 to 1 generate
    rx_pad_s(e) <= transport pad_s(1-e) after propagation_c;
  end generate;

  quad: nsl_transceiver.cluster.transceiver_cluster
    generic map(
      config_c => config_c,
      ref_clock_c => ref_clock_c
      )
    port map(
      reset_n_i => reset_n_i,

      ref_clock_i(0) => clock_i,
      ref_clock_i(1) => clock_i,

      lane_tx_o => pad_s,
      lane_rx_i => rx_pad_s,

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

  -- A lane in this mode ignores its data bus, so the only thing
  -- driven towards it is which pattern to send and whether to spoil
  -- a bit of it.
  tx_m_s <= (others => (data => (others => (others => '-')),
                        aux => (others => (others => '-')),
                        valid => '0',
                        pcs_reset_n => '1',
                        control => (others => '0'),
                        control_h => (others => '0'),
                        c2i_clock => '0',
                        prbs_select => tx_mode_s,
                        prbs_force_error => force_error_s));

  rx_s_s <= (others => (ready => '1',
                        pcs_reset_n => '1',
                        align_trigger => '0',
                        chbond_start => '0',
                        control => (others => '0'),
                        prbs_select => rx_mode_s,
                        prbs_error_reset => error_reset_s));

  sequencer: process
    constant ctxt : log_context := label_c;
    variable cycles_v : natural;
    variable errors_v : natural;

    procedure wait_locked(budget : natural; what : string) is
      variable waited_v : natural;
    begin
      waited_v := 0;
      while rx_m_s(0).prbs_locked /= '1' or rx_m_s(1).prbs_locked /= '1' loop
        wait until rising_edge(lane_rx_clock_s(0));
        waited_v := waited_v + 1;
        assert waited_v < budget
          report what & ": lane 0 reports "
          & std_ulogic'image(rx_m_s(0).prbs_locked) & " and lane 1 "
          & std_ulogic'image(rx_m_s(1).prbs_locked)
          & " after " & integer'image(waited_v) & " words, with pma lock "
          & std_ulogic'image(rx_m_s(0).pma_lock) & " / "
          & std_ulogic'image(rx_m_s(1).pma_lock)
          severity failure;
      end loop;

      log_info(ctxt, what & " took " & integer'image(waited_v) & " words");
    end procedure;

    -- Both directions have to come back clean: a lane that generated
    -- a pattern but could not check one, or the other way round,
    -- would pass a test watching one end.
    procedure run_clean(word_count : natural; what : string) is
    begin
      for i in 0 to word_count-1 loop
        wait until rising_edge(lane_rx_clock_s(0));

        for e in 0 to 1 loop
          assert rx_m_s(e).prbs_error = '0'
            report what & ": lane " & integer'image(e)
            & " could not predict a word on a line nothing had touched"
            severity failure;
          assert rx_m_s(e).prbs_locked = '1'
            report what & ": lane " & integer'image(e)
            & " lost a pattern nothing had interrupted"
            severity failure;
        end loop;
      end loop;
    end procedure;
  begin
    done_o <= '0';
    tx_mode_s <= mode_c;
    rx_mode_s <= mode_c;
    force_error_s <= '0';
    error_reset_s <= '0';

    wait until reset_n_i = '1';

    wait_locked(4096, "finding the pattern across the cable");
    run_clean(256, "running clean");

    -- One bit of one word goes out wrong. It lands on a bit
    -- boundary, so it adds or removes a transition only where the
    -- recovery loop expects one and the loop keeps its phase: the
    -- far end sees exactly one wrong bit and nothing else.
    wait until falling_edge(lane_clock_s(0));
    force_error_s <= '1';
    wait until falling_edge(lane_clock_s(0));
    force_error_s <= '0';

    errors_v := 0;
    for i in 0 to 255 loop
      wait until rising_edge(lane_rx_clock_s(1));
      if rx_m_s(1).prbs_error = '1' then
        errors_v := errors_v + 1;
      end if;
    end loop;

    assert errors_v = 1
      report integer'image(errors_v)
      & " words came back unpredictable from a single spoiled bit"
      severity failure;

    assert rx_m_s(1).prbs_locked = '1'
      report "the far end lost the pattern over one bit"
      severity failure;

    log_info(ctxt, "a spoiled bit was reported once at the far end");

    run_clean(256, "running clean after a spoiled bit");

    -- Pointed at a different pattern, the far end has to give up:
    -- one it finds anyway would mean it is not really predicting.
    wait until falling_edge(lane_clock_s(0));
    rx_mode_s <= other_mode_c;

    cycles_v := 0;
    while rx_m_s(1).prbs_locked /= '0' loop
      wait until rising_edge(lane_rx_clock_s(1));
      cycles_v := cycles_v + 1;
      assert cycles_v < 1024
        report "the far end kept reporting a pattern it was no longer"
        & " looking for"
        severity failure;
    end loop;

    log_info(ctxt, "gave up on the wrong pattern in "
             & integer'image(cycles_v) & " words");

    -- And a line told to carry nothing stops moving, which is what
    -- the lane calls electrically idle.
    wait until falling_edge(lane_clock_s(0));
    tx_mode_s <= PRBS_NONE;
    rx_mode_s <= mode_c;

    cycles_v := 0;
    while rx_m_s(1).elec_idle /= '1' loop
      wait until rising_edge(lane_rx_clock_s(1));
      cycles_v := cycles_v + 1;
      assert cycles_v < 1024
        report "a lane asked for no pattern kept its line moving"
        severity failure;
    end loop;

    assert rx_m_s(1).prbs_locked = '0'
      report "the far end still reports a pattern on a line that"
      & " stopped moving"
      severity failure;

    log_info(ctxt, "a line asked for no pattern went idle in "
             & integer'image(cycles_v) & " words");

    -- Both ends back on the same pattern, and the link has to come
    -- back without anything being reset.
    wait until falling_edge(lane_clock_s(0));
    tx_mode_s <= mode_c;
    error_reset_s <= '1';
    wait until falling_edge(lane_clock_s(0));
    error_reset_s <= '0';

    wait_locked(4096, "finding the pattern again");
    run_clean(256, "running clean again");

    log_info(ctxt, "carried " & prbs_mode_t'image(mode_c)
             & " over a " & integer'image(line_rate_mbps_c)
             & " Mbps lane " & integer'image(data_byte_count_c)
             & " bytes wide, both ways");

    done_o <= '1';
    wait;
  end process;

end architecture;
