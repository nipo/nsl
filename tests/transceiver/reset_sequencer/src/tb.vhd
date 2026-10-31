library ieee;
use ieee.std_logic_1164.all;

library nsl_simulation, nsl_transceiver;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;

-- The reset sequencers express a vendor's documented bring-up order
-- as a state machine. They reach no primitive, so what the order is
-- can be checked here rather than on a board, which is where a lane
-- that silently never comes up is at its most expensive to debug.
entity tb is
end tb;

architecture arch of tb is

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 4);

begin

  -- GTPE2 common block ---------------------------------------------

  pll_sequencer: block

    constant delay500ns_c : natural := 10;
    constant delay_pll_rst_c : natural := 3;

    signal pd_s, rst_s, ready_s : std_ulogic;

  begin

    dut: nsl_transceiver.transceiver_utils.gtpe2_pll_reset_fsm
      generic map(
        delay500ns_c => delay500ns_c,
        delay_pll_rst_c => delay_pll_rst_c
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,
        pll_pd_o => pd_s,
        pll_rst_o => rst_s,
        done_o => ready_s
        );

    check: process
      constant ctxt : log_context := "gtpe2 pll reset";
      variable elapsed_v, powerup_v : natural;
      variable reset_seen_v : boolean;
    begin
      done_s(0) <= '0';

      wait until reset_n_s = '1';

      assert_equal(ctxt, "powered down out of reset", pd_s, '1', FAILURE);
      assert_equal(ctxt, "not done out of reset", ready_s, '0', FAILURE);

      -- Resetting a powered-down PLL does nothing, so the order of
      -- the two is the whole point of the sequencer.
      elapsed_v := 0;
      powerup_v := 0;
      reset_seen_v := false;
      while ready_s /= '1' loop
        wait until rising_edge(clock_s);
        elapsed_v := elapsed_v + 1;
        assert elapsed_v < 4 * delay500ns_c + delay_pll_rst_c + 16
          report "gtpe2 pll reset: the sequence never completed"
          severity failure;
        if pd_s = '0' and powerup_v = 0 then
          powerup_v := elapsed_v;
        end if;
        if rst_s = '1' then
          assert_equal(ctxt, "powered up before the reset pulse",
                       pd_s, '0', FAILURE);
          reset_seen_v := true;
        end if;
      end loop;

      assert reset_seen_v
        report "gtpe2 pll reset: the PLL reset was never pulsed"
        severity failure;

      -- The hold times are what makes the sequencer worth having: one
      -- that merely ordered the steps would finish in a handful of
      -- cycles.
      assert powerup_v >= delay500ns_c
        report "gtpe2 pll reset: the power-down hold was cut short"
        severity failure;
      assert elapsed_v >= 2 * delay500ns_c
        report "gtpe2 pll reset: a hold was skipped"
        severity failure;

      assert_equal(ctxt, "reset released once done", rst_s, '0', FAILURE);
      assert_equal(ctxt, "powered up once done", pd_s, '0', FAILURE);

      log_info(ctxt, "brought the plls up in "
               & integer'image(elapsed_v) & " cycles");

      done_s(0) <= '1';
      wait;
    end process;

  end block;

  -- GTHE4 channel PLL ----------------------------------------------

  cpll_sequencer: block

    constant hold_delay_c : natural := 12;

    signal power_good_s, pd_s, ready_s : std_ulogic;

  begin

    dut: nsl_transceiver.transceiver_utils.gthe4_cpll_reset_fsm
      generic map(
        hold_delay_c => hold_delay_c
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,
        power_good_i => power_good_s,
        pll_pd_o => pd_s,
        done_o => ready_s
        );

    check: process
      constant ctxt : log_context := "gthe4 cpll reset";
      variable elapsed_v : natural;
    begin
      done_s(1) <= '0';
      power_good_s <= '0';

      wait until reset_n_s = '1';

      assert_equal(ctxt, "powered down out of reset", pd_s, '1', FAILURE);

      -- Both conditions gate the power-up, so a supply that never
      -- comes good must leave the sequencer waiting.
      for i in 0 to 2 * hold_delay_c loop
        wait until rising_edge(clock_s);
      end loop;

      assert_equal(ctxt, "still powered down without power good",
                   pd_s, '1', FAILURE);
      assert_equal(ctxt, "not done without power good",
                   ready_s, '0', FAILURE);

      power_good_s <= '1';

      elapsed_v := 0;
      while ready_s /= '1' loop
        wait until rising_edge(clock_s);
        elapsed_v := elapsed_v + 1;
        assert elapsed_v < 16
          report "gthe4 cpll reset: power good never released the sequence"
          severity failure;
      end loop;

      assert_equal(ctxt, "powered up once done", pd_s, '0', FAILURE);

      log_info(ctxt, "powered the cpll up "
               & integer'image(elapsed_v) & " cycles after power good");

      done_s(1) <= '1';
      wait;
    end process;

  end block;

  -- GTPE2 channel --------------------------------------------------

  channel_sequencer: block

    constant timeout_delay_c : natural := 1024;
    constant drp_addr_c : std_ulogic_vector(8 downto 0) := "000010001";
    constant drp_initial_c : std_ulogic_vector(15 downto 0) := x"5a5a";

    signal pll_locked_s, pll_reset_done_s, pma_rst_done_s : std_ulogic;
    signal gtp_rst_s : std_ulogic;
    signal drp_addr_s : std_ulogic_vector(8 downto 0);
    signal drp_en_s, drp_wr_s, drp_rdy_s : std_ulogic;
    signal drp_wdata_s, drp_rdata_s : std_ulogic_vector(15 downto 0);

  begin

    dut: nsl_transceiver.transceiver_utils.gtpe2_reset_fsm
      generic map(
        timeout_delay_c => timeout_delay_c
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,
        pll_locked_i => pll_locked_s,
        pll_reset_done_i => pll_reset_done_s,
        pma_rst_done_i => pma_rst_done_s,
        gtp_rst_o => gtp_rst_s,
        drp_addr_o => drp_addr_s,
        drp_en_o => drp_en_s,
        drp_wr_o => drp_wr_s,
        drp_wdata_o => drp_wdata_s,
        drp_rdata_i => drp_rdata_s,
        drp_rdy_i => drp_rdy_s
        );

    -- Stands in for the channel's PMA. Its reset-done flag drops
    -- while the reset is asserted, and pulses once more after the
    -- reset is released: that pulse is what the sequencer waits for
    -- before putting the register it modified back.
    pma: process
    begin
      pll_locked_s <= '0';
      pll_reset_done_s <= '0';
      pma_rst_done_s <= '0';

      wait until reset_n_s = '1';

      for i in 0 to 7 loop
        wait until rising_edge(clock_s);
      end loop;
      pll_locked_s <= '1';
      pll_reset_done_s <= '1';

      wait until gtp_rst_s = '1';
      wait until gtp_rst_s = '0';

      for i in 0 to 3 loop
        wait until rising_edge(clock_s);
      end loop;
      pma_rst_done_s <= '1';

      for i in 0 to 3 loop
        wait until rising_edge(clock_s);
      end loop;
      pma_rst_done_s <= '0';

      for i in 0 to 3 loop
        wait until rising_edge(clock_s);
      end loop;
      pma_rst_done_s <= '1';

      wait;
    end process;

    -- The DRP register the sequencer modifies, and the checker for
    -- the transaction it runs on it: the sequence is a
    -- read-modify-write around the PMA reset, so the model and the
    -- scoreboard are the same thing.
    drp: process
      constant ctxt : log_context := "gtpe2 channel reset";
      variable reg_v : std_ulogic_vector(15 downto 0);
      variable writes_v : natural;
    begin
      done_s(2) <= '0';
      drp_rdy_s <= '0';
      drp_rdata_s <= (others => '0');
      reg_v := drp_initial_c;
      writes_v := 0;

      loop
        wait until rising_edge(clock_s);

        drp_rdy_s <= '0';

        if drp_en_s = '1' then
          assert_equal(ctxt, "accessed register address",
                       drp_addr_s, drp_addr_c, FAILURE);

          if drp_wr_s = '1' then
            writes_v := writes_v + 1;

            if writes_v = 1 then
              assert_equal(ctxt, "channel held in reset over the write",
                           gtp_rst_s, '1', FAILURE);
              assert_equal(ctxt, "the write clears bit 11",
                           drp_wdata_s(11), '0', FAILURE);
              assert_equal(ctxt, "the write leaves the bits above alone",
                           drp_wdata_s(15 downto 12),
                           drp_initial_c(15 downto 12), FAILURE);
              assert_equal(ctxt, "the write leaves the bits below alone",
                           drp_wdata_s(10 downto 0),
                           drp_initial_c(10 downto 0), FAILURE);
            else
              assert_equal(ctxt, "the channel is out of reset by the restore",
                           gtp_rst_s, '0', FAILURE);
              assert_equal(ctxt, "the restore puts the register back",
                           drp_wdata_s, drp_initial_c, FAILURE);
            end if;

            reg_v := drp_wdata_s;
          end if;

          drp_rdata_s <= reg_v;
          drp_rdy_s <= '1';

          exit when writes_v = 2;
        end if;
      end loop;

      assert_equal(ctxt, "only two writes were needed", writes_v, 2, FAILURE);

      log_info(ctxt, "read, modified, reset and restored "
               & "the channel's pma register");

      done_s(2) <= '1';
      wait;
    end process;

  end block;

  -- GTHE4 channel, one direction -----------------------------------

  direction_sequencer: block

    constant timeout_delay_c : natural := 1024;
    constant gt_pwr_delay_c : natural := 8;

    signal power_good_s, pll_locked_s, pll_reset_done_s : std_ulogic;
    signal pma_rst_done_s, rst_done_s, progdiv_rst_done_s : std_ulogic;
    signal gth_rst_s, progdiv_rst_s, ready_s : std_ulogic;

  begin

    dut: nsl_transceiver.transceiver_utils.gthe4_reset_fsm
      generic map(
        timeout_delay_c => timeout_delay_c,
        gt_pwr_delay_c => gt_pwr_delay_c
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,
        power_good_i => power_good_s,
        pll_locked_i => pll_locked_s,
        pll_reset_done_i => pll_reset_done_s,
        pma_rst_done_i => pma_rst_done_s,
        rst_done_i => rst_done_s,
        progdiv_rst_done_i => progdiv_rst_done_s,
        gth_rst_o => gth_rst_s,
        progdiv_rst_o => progdiv_rst_s,
        ready_o => ready_s
        );

    -- Stands in for the channel: the reset-done flags drop while the
    -- reset is asserted and come back a few cycles after it is
    -- released. The programmable divider answers the same way.
    channel: process(clock_s)
      variable delay_v : natural range 0 to 4 := 0;
    begin
      if rising_edge(clock_s) then
        if gth_rst_s = '1' then
          delay_v := 4;
          pma_rst_done_s <= '0';
          rst_done_s <= '0';
        elsif delay_v /= 0 then
          delay_v := delay_v - 1;
        else
          pma_rst_done_s <= '1';
          rst_done_s <= '1';
        end if;

        if progdiv_rst_s = '1' then
          progdiv_rst_done_s <= '0';
        else
          progdiv_rst_done_s <= '1';
        end if;
      end if;
    end process;

    check: process
      constant ctxt : log_context := "gthe4 direction reset";
      variable elapsed_v : natural;
    begin
      done_s(3) <= '0';
      power_good_s <= '0';
      pll_locked_s <= '0';
      pll_reset_done_s <= '0';

      wait until reset_n_s = '1';
      wait until rising_edge(clock_s);

      assert_equal(ctxt, "channel held in reset out of reset",
                   gth_rst_s, '1', FAILURE);
      assert_equal(ctxt, "divider held in reset out of reset",
                   progdiv_rst_s, '1', FAILURE);
      assert_equal(ctxt, "not ready out of reset", ready_s, '0', FAILURE);

      -- A channel released against an unlocked PLL comes up on
      -- whatever rate the PLL happens to be sweeping through.
      for i in 0 to 31 loop
        wait until rising_edge(clock_s);
        assert_equal(ctxt, "channel held while the pll is unlocked",
                     gth_rst_s, '1', FAILURE);
        assert_equal(ctxt, "divider held while the pll is unlocked",
                     progdiv_rst_s, '1', FAILURE);
      end loop;

      pll_locked_s <= '1';
      pll_reset_done_s <= '1';

      -- Power good gates the release just as it does on the CPLL.
      for i in 0 to 15 loop
        wait until rising_edge(clock_s);
        assert_equal(ctxt, "channel held without power good",
                     gth_rst_s, '1', FAILURE);
      end loop;
      assert_equal(ctxt, "divider released once the pll is locked",
                   progdiv_rst_s, '0', FAILURE);

      power_good_s <= '1';

      elapsed_v := 0;
      while ready_s /= '1' loop
        wait until rising_edge(clock_s);
        elapsed_v := elapsed_v + 1;
        assert elapsed_v < gt_pwr_delay_c + 32
          report "gthe4 direction reset: power good never released the sequence"
          severity failure;
      end loop;

      assert_equal(ctxt, "channel released once ready",
                   gth_rst_s, '0', FAILURE);
      assert elapsed_v >= gt_pwr_delay_c
        report "gthe4 direction reset: the settling delay was cut short"
        severity failure;

      log_info(ctxt, "brought the direction up "
               & integer'image(elapsed_v) & " cycles after power good");

      -- A PLL that loses lock has taken the lane down with it, so the
      -- sequencer has to run again rather than keep reporting ready.
      pll_locked_s <= '0';

      elapsed_v := 0;
      while ready_s /= '0' loop
        wait until rising_edge(clock_s);
        elapsed_v := elapsed_v + 1;
        assert elapsed_v < 16
          report "gthe4 direction reset: losing pll lock left the lane ready"
          severity failure;
      end loop;

      assert_equal(ctxt, "channel reset again after losing lock",
                   gth_rst_s, '1', FAILURE);

      log_info(ctxt, "re-armed the sequence on loss of pll lock");

      done_s(3) <= '1';
      wait;
    end process;

  end block;

  -- Stall watchdog -------------------------------------------------

  watchdog: block

    constant timeout_delay_c : natural := 32;
    constant gt_pwr_delay_c : natural := 4;

    signal pma_rst_done_s, rst_done_s : std_ulogic;
    signal gth_rst_s, ready_s : std_ulogic;

  begin

    -- Nothing ever answers this instance: power is never good, so the
    -- sequence stalls in the middle and the watchdog is the only
    -- thing that can move it.
    dut: nsl_transceiver.transceiver_utils.gthe4_reset_fsm
      generic map(
        timeout_delay_c => timeout_delay_c,
        gt_pwr_delay_c => gt_pwr_delay_c
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,
        power_good_i => '0',
        pll_locked_i => '1',
        pll_reset_done_i => '1',
        pma_rst_done_i => pma_rst_done_s,
        rst_done_i => rst_done_s,
        gth_rst_o => gth_rst_s,
        progdiv_rst_o => open,
        ready_o => ready_s
        );

    pma_rst_done_s <= '0';
    rst_done_s <= '0';

    check: process
      constant ctxt : log_context := "gthe4 watchdog";
    begin
      done_s(4) <= '0';

      wait until reset_n_s = '1';

      -- The sequence has to keep restarting, and the channel has to
      -- stay in reset throughout: a stalled bring-up that let go of
      -- the channel would hand the fabric a lane running on nothing.
      for i in 0 to 4 * timeout_delay_c loop
        wait until rising_edge(clock_s);
        assert_equal(ctxt, "channel held while the sequence stalls",
                     gth_rst_s, '1', FAILURE);
        assert_equal(ctxt, "never ready while the sequence stalls",
                     ready_s, '0', FAILURE);
      end loop;

      log_info(ctxt, "survived "
               & integer'image(4 * timeout_delay_c)
               & " cycles of a stalled bring-up");

      done_s(4) <= '1';
      wait;
    end process;

  end block;

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
