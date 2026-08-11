library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_simulation, nsl_transceiver, nsl_cuff, nsl_line_coding, nsl_data;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;
use nsl_data.bytestream.all;
use nsl_line_coding.ibm_8b10b.all;

entity tb is
end tb;

architecture arch of tb is

  constant lane_count_c : natural := 2;
  constant payload_c : byte_string := from_hex("00112233445566778899aabbccddeeff");

  -- Idle cycles the stimulus sends before the payload, and the
  -- budgets the checker allows before declaring the loopback dead.
  -- Syncing on the idle run has to happen while the lead-in is still
  -- running, so its budget stays under the lead-in; waiting for the
  -- payload then spans whatever lead-in is left, plus the codec
  -- pipeline latency.
  constant idle_lead_in_c : natural := 64;
  constant idle_timeout_c : natural := 48;
  constant payload_timeout_c : natural := idle_lead_in_c + 32;

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 2);

  signal tx_word_s : nsl_line_coding.ibm_8b10b.data_t;
  signal tx_lane_s, rx_lane_s : nsl_cuff.protocol.cuff_code_vector(0 to lane_count_c-1);

  signal tx_m_s : nsl_transceiver.lane.tx_master_vector(0 to lane_count_c-1);
  signal tx_s_s : nsl_transceiver.lane.tx_slave_vector(0 to lane_count_c-1);
  signal rx_m_s : nsl_transceiver.lane.rx_master_vector(0 to lane_count_c-1);
  signal rx_s_s : nsl_transceiver.lane.rx_slave_vector(0 to lane_count_c-1);

  type symbol_vector is array (natural range <>) of nsl_line_coding.ibm_8b10b.data_t;
  signal recovered_s : symbol_vector(0 to lane_count_c-1);

begin

  lanes: for lane_idx in 0 to lane_count_c-1 generate

    -- Stands in for the CUFF lane transmitter: the adapter expects
    -- 10-bit code words on its CUFF side.
    tx_encoder: nsl_line_coding.ibm_8b10b.ibm_8b10b_encoder
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,
        valid_i => '1',
        data_i => tx_word_s,
        valid_o => open,
        data_o => tx_lane_s(lane_idx)
        );

    -- Stands in for a transceiver that carries the byte and its K
    -- flag transparently, which is what the lane contract promises
    -- an 8b/10b-capable primitive does.
    rx_m_s(lane_idx) <= (
      data => tx_m_s(lane_idx).data,
      aux => tx_m_s(lane_idx).aux,
      valid => '1',
      pma_lock => '1',
      pcs_aligned => '1',
      elec_idle => '0',
      status => (others => '0')
      );

    -- Stands in for the CUFF lane receiver.
    rx_decoder: nsl_line_coding.ibm_8b10b.ibm_8b10b_decoder
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,
        valid_i => '1',
        data_i => rx_lane_s(lane_idx),
        valid_o => open,
        data_o => recovered_s(lane_idx),
        code_error_o => open,
        disparity_error_o => open
        );

  end generate;

  tx_s_s <= (others => (ready => '1',
                        pll_lock => '1',
                        status => (others => '0')));

  dut: nsl_transceiver.cuff.cuff_adapter
    generic map(
      lane_count_c => lane_count_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      tx_lane_i => tx_lane_s,
      rx_lane_o => rx_lane_s,

      tx_m_o => tx_m_s,
      tx_s_i => tx_s_s,
      rx_m_i => rx_m_s,
      rx_s_o => rx_s_s
      );

  stim: process
  begin
    done_s(0) <= '0';
    tx_word_s <= K28_5;

    wait until reset_n_s = '1';

    for i in 0 to idle_lead_in_c-1 loop
      wait until falling_edge(clock_s);
    end loop;

    for i in payload_c'range loop
      wait until falling_edge(clock_s);
      tx_word_s <= data(payload_c(i));
    end loop;

    wait until falling_edge(clock_s);
    tx_word_s <= K28_5;

    for i in 0 to 63 loop
      wait until falling_edge(clock_s);
    end loop;

    done_s(0) <= '1';
    wait;
  end process;

  datapath_check: process
    constant ctxt : log_context := "cuff adapter";
    variable idle_run_v, elapsed_v : natural;
  begin
    done_s(1) <= '0';

    wait until reset_n_s = '1';

    -- A run of recovered idles means the codec pipelines on both
    -- sides of the adapter have flushed and are tracking the stream.
    idle_run_v := 0;
    elapsed_v := 0;
    while idle_run_v < 8 loop
      wait until rising_edge(clock_s);
      elapsed_v := elapsed_v + 1;
      assert elapsed_v < idle_timeout_c
        report "cuff adapter: idles never came back around the loopback"
        severity failure;
      if recovered_s(0) = K28_5 then
        idle_run_v := idle_run_v + 1;
      else
        idle_run_v := 0;
      end if;
    end loop;

    -- The payload is the only run of data words in an otherwise idle
    -- stream, so its first word marks the pipeline alignment.
    elapsed_v := 0;
    loop
      wait until rising_edge(clock_s);
      elapsed_v := elapsed_v + 1;
      assert elapsed_v < payload_timeout_c
        report "cuff adapter: payload never came back around the loopback"
        severity failure;
      exit when recovered_s(0).control = '0';
    end loop;

    for i in payload_c'range loop
      for lane_idx in 0 to lane_count_c-1 loop
        assert_equal(ctxt,
                     "lane " & integer'image(lane_idx)
                     & " word " & integer'image(i) & " is data",
                     recovered_s(lane_idx).control, '0', FAILURE);
        assert_equal(ctxt,
                     "lane " & integer'image(lane_idx)
                     & " word " & integer'image(i),
                     recovered_s(lane_idx).data, payload_c(i), FAILURE);
      end loop;
      exit when i = payload_c'high;
      wait until rising_edge(clock_s);
    end loop;

    log_info(ctxt, "round trip of "
             & integer'image(payload_c'length) & " words on "
             & integer'image(lane_count_c) & " lanes");

    done_s(1) <= '1';
    wait;
  end process;

  config_check: process
    constant ctxt : log_context := "cluster config";

    constant enabled_pll_c : nsl_transceiver.cluster.pll_config_t := (
      enabled => true,
      ref_clock_index => 0,
      target_vco_mhz => 2500
      );

    constant lane_c : nsl_transceiver.lane.config_t := nsl_transceiver.lane.config(
      data_byte_count => 1,
      encoding => nsl_transceiver.lane.ENCODING_8B10B,
      line_rate_mbps => 1250
      );

    variable lane_v : nsl_transceiver.lane.config_t;
  begin
    done_s(2) <= '0';

    assert_equal(ctxt, "lane on enabled pll",
                 nsl_transceiver.cluster.is_valid(
                   nsl_transceiver.cluster.config(
                     plls => (0 => enabled_pll_c),
                     lanes => (0 => lane_c),
                     user_clock_group_count => 1)),
                 true, FAILURE);

    assert_equal(ctxt, "disabled lane ignores routing",
                 nsl_transceiver.cluster.is_valid(
                   nsl_transceiver.cluster.config(
                     plls => (0 => nsl_transceiver.cluster.disabled_pll_c),
                     lanes => (0 => nsl_transceiver.lane.disabled_lane_c),
                     user_clock_group_count => 0)),
                 true, FAILURE);

    assert_equal(ctxt, "lane on disabled pll",
                 nsl_transceiver.cluster.is_valid(
                   nsl_transceiver.cluster.config(
                     plls => (0 => nsl_transceiver.cluster.disabled_pll_c),
                     lanes => (0 => lane_c),
                     user_clock_group_count => 1)),
                 false, FAILURE);

    lane_v := lane_c;
    lane_v.pll_index := 1;
    assert_equal(ctxt, "lane on out-of-range pll",
                 nsl_transceiver.cluster.is_valid(
                   nsl_transceiver.cluster.config(
                     plls => (0 => enabled_pll_c),
                     lanes => (0 => lane_v),
                     user_clock_group_count => 1)),
                 false, FAILURE);

    lane_v := lane_c;
    lane_v.user_clock_group_index := 1;
    assert_equal(ctxt, "lane on out-of-range user clock group",
                 nsl_transceiver.cluster.is_valid(
                   nsl_transceiver.cluster.config(
                     plls => (0 => enabled_pll_c),
                     lanes => (0 => lane_v),
                     user_clock_group_count => 1)),
                 false, FAILURE);

    done_s(2) <= '1';
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
