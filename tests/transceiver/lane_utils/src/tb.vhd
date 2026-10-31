library ieee;
use ieee.std_logic_1164.all;

library nsl_simulation, nsl_transceiver;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;

-- The word aligner and the gearbox are the two pieces of a vendor
-- backend that are plain logic, so they are checkable without the
-- primitive they sit next to.
entity tb is
end tb;

architecture arch of tb is

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 5);

begin

  -- Word alignment supervisor --------------------------------------

  aligner: block

    constant stabilization_count_c : natural := 16;
    constant flush_count_c : natural := 8;
    constant lost_count_c : natural := 24;

    signal valid_s, restart_s, align_en_s, ready_s : std_ulogic;

  begin

    dut: nsl_transceiver.transceiver_utils.lane_aligner
      generic map(
        stabilization_count_c => stabilization_count_c,
        flush_count_c => flush_count_c,
        lost_count_c => lost_count_c
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,
        valid_i => valid_s,
        restart_i => restart_s,
        align_en_o => align_en_s,
        ready_o => ready_s
        );

    check: process
      constant ctxt : log_context := "lane aligner";
      variable elapsed_v : natural;
    begin
      done_s(0) <= '0';
      valid_s <= '0';
      restart_s <= '0';

      wait until reset_n_s = '1';
      wait until rising_edge(clock_s);

      assert_equal(ctxt, "aligning out of reset", align_en_s, '1', FAILURE);
      assert_equal(ctxt, "not ready out of reset", ready_s, '0', FAILURE);

      -- An aligner that froze on a stream that never decodes would
      -- lock the lane onto a word boundary chosen at random.
      for i in 0 to 4 * stabilization_count_c loop
        wait until rising_edge(clock_s);
        assert_equal(ctxt, "still aligning without valid data",
                     align_en_s, '1', FAILURE);
        assert_equal(ctxt, "not ready without valid data",
                     ready_s, '0', FAILURE);
      end loop;

      -- The stabilization count has to be reached consecutively: a
      -- stream that decodes half the time is not aligned.
      for burst in 0 to 3 loop
        valid_s <= '1';
        for i in 0 to stabilization_count_c - 4 loop
          wait until rising_edge(clock_s);
        end loop;
        valid_s <= '0';
        wait until rising_edge(clock_s);
        assert_equal(ctxt, "not ready on an intermittent stream",
                     ready_s, '0', FAILURE);
      end loop;

      valid_s <= '1';

      elapsed_v := 0;
      while ready_s /= '1' loop
        wait until rising_edge(clock_s);
        elapsed_v := elapsed_v + 1;
        assert elapsed_v < flush_count_c + 2 * stabilization_count_c
          report "lane aligner: a steady stream never brought the lane up"
          severity failure;
      end loop;

      assert elapsed_v >= stabilization_count_c
        report "lane aligner: the stabilization count was cut short"
        severity failure;

      -- Alignment is frozen once found, so the comma aligner cannot
      -- re-frame the stream on a comma that appears inside a word.
      assert_equal(ctxt, "alignment frozen once ready",
                   align_en_s, '0', FAILURE);

      log_info(ctxt, "aligned in " & integer'image(elapsed_v)
               & " cycles of a steady stream");

      -- A link that goes away has to re-arm the aligner, or the lane
      -- comes back framed on the boundary the previous partner used.
      valid_s <= '0';

      elapsed_v := 0;
      while ready_s /= '0' loop
        wait until rising_edge(clock_s);
        elapsed_v := elapsed_v + 1;
        assert elapsed_v < 2 * lost_count_c
          report "lane aligner: losing the stream left the lane aligned"
          severity failure;
      end loop;

      assert elapsed_v >= lost_count_c
        report "lane aligner: the lane was dropped before the lost count"
        severity failure;
      assert_equal(ctxt, "aligning again after losing the stream",
                   align_en_s, '1', FAILURE);

      log_info(ctxt, "re-armed " & integer'image(elapsed_v)
               & " cycles after the stream stopped");

      -- Bring it back up, so the explicit restart can be checked
      -- from a stable state.
      valid_s <= '1';
      while ready_s /= '1' loop
        wait until rising_edge(clock_s);
      end loop;

      restart_s <= '1';
      wait until rising_edge(clock_s);
      restart_s <= '0';

      elapsed_v := 0;
      while ready_s /= '0' loop
        wait until rising_edge(clock_s);
        elapsed_v := elapsed_v + 1;
        assert elapsed_v < 4
          report "lane aligner: a restart left the lane aligned"
          severity failure;
      end loop;

      assert_equal(ctxt, "restart resumes aligning",
                   align_en_s, '1', FAILURE);

      while ready_s /= '1' loop
        wait until rising_edge(clock_s);
      end loop;

      log_info(ctxt, "re-aligned after an explicit restart");

      done_s(0) <= '1';
      wait;
    end process;

  end block;

  -- Alignment bypass -----------------------------------------------

  bypass: block

    signal align_en_s, ready_s : std_ulogic;

  begin

    dut: nsl_transceiver.transceiver_utils.lane_aligner
      generic map(
        bypass_c => true,
        stabilization_count_c => 16,
        flush_count_c => 8,
        lost_count_c => 24
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,
        valid_i => '0',
        restart_i => '0',
        align_en_o => align_en_s,
        ready_o => ready_s
        );

    -- A stream taken from a far-end PMA loopback is not comma-framed,
    -- so a bypassed aligner has to report ready on a stream that
    -- never decodes rather than hold the lane down forever.
    check: process
      constant ctxt : log_context := "lane aligner bypass";
    begin
      done_s(1) <= '0';

      wait until reset_n_s = '1';

      for i in 0 to 63 loop
        wait until rising_edge(clock_s);
        assert_equal(ctxt, "never aligns", align_en_s, '0', FAILURE);
        assert_equal(ctxt, "always ready", ready_s, '1', FAILURE);
      end loop;

      log_info(ctxt, "passed the stream through unaligned");

      done_s(1) <= '1';
      wait;
    end process;

  end block;

  -- Interface width conversion -------------------------------------

  -- The widths the GT backends ask for. A two-byte lane on a 16-bit
  -- interface and a four-byte lane on a 32-bit one convert nothing,
  -- and are here because a gearbox that only worked when it had
  -- something to do would be worse than useless; the mismatched
  -- pairs are what it exists for.
  byte_on_16: entity work.gearbox_bench
    generic map(
      data_byte_count_c => 1,
      interface_width_c => 16
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      done_o => done_s(2)
      );

  two_on_16: entity work.gearbox_bench
    generic map(
      data_byte_count_c => 2,
      interface_width_c => 16
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      done_o => done_s(3)
      );

  two_on_32: entity work.gearbox_bench
    generic map(
      data_byte_count_c => 2,
      interface_width_c => 32
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      done_o => done_s(4)
      );

  four_on_32: entity work.gearbox_bench
    generic map(
      data_byte_count_c => 4,
      interface_width_c => 32
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      done_o => done_s(5)
      );

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
