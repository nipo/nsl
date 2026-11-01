library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_simulation, nsl_transceiver, nsl_data;
use nsl_data.bytestream.all;
use nsl_data.prbs.all;
use nsl_transceiver.lane.all;
use nsl_simulation.logging.all;

-- The fabric pattern generator and checker a lane in ENCODING_PRBS
-- falls back on when its transceiver has no generator of its own.
--
-- Both are built from the tap depths read out of the polynomials in
-- nsl_data.prbs, so the first thing checked is that those depths
-- really do produce the sequence they are supposed to: a generator
-- whose taps were read off wrongly still produces a repeating
-- pattern, and a checker built from the same wrong taps still agrees
-- with it. Only the period tells them apart.
entity tb is
end tb;

architecture arch of tb is

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 5);

  -- A PRBS-7 generator watched on its own, to measure what it emits.
  signal period_data_s : byte_string(0 to 0);
  signal period_valid_s : std_ulogic;

begin

  period_generator: nsl_transceiver.prbs.prbs_generator
    generic map(
      byte_count_c => 1
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      mode_i => PRBS_7,
      force_error_i => '0',

      data_o => period_data_s,
      valid_o => period_valid_s
      );

  -- A maximal-length sequence of order 7 repeats every 127 bits and
  -- never sooner. Anything shorter means the generator is walking a
  -- shorter cycle than the polynomial's, which is what reading the
  -- wrong tap out of it produces.
  period: process
    constant ctxt : log_context := "prbs 7 period";
    constant capture_c : natural := 512;
    constant order_c : natural := 7;
    -- The generator leaves reset with every bit of its history set,
    -- which is the state the reference has to start from too.
    constant seed_c : prbs_state(order_c-1 downto 0) := (others => '1');
    variable bits_v : std_ulogic_vector(0 to capture_c-1);
    variable reference_v : std_ulogic_vector(0 to order_c + capture_c - 1);
    variable byte_v : byte;
    variable matches_v : boolean;
    variable period_v : natural;
  begin
    done_s(0) <= '0';

    wait until reset_n_s = '1';

    for i in 0 to capture_c/8 - 1 loop
      wait until rising_edge(clock_s) and period_valid_s = '1';
      byte_v := period_data_s(0);
      for b in 0 to 7 loop
        bits_v(i * 8 + b) := byte_v(b);
      end loop;
    end loop;

    period_v := 0;
    for p in 1 to 255 loop
      matches_v := true;
      for i in 0 to capture_c - 1 - p loop
        if bits_v(i) /= bits_v(i + p) then
          matches_v := false;
        end if;
      end loop;

      if matches_v and period_v = 0 then
        period_v := p;
      end if;
    end loop;

    assert period_v = 127
      report "the generator walks a cycle of " & integer'image(period_v)
      & " bits, where an order 7 pattern walks 127"
      severity failure;

    log_info(ctxt, "walks its full 127 bit cycle and no shorter one");

    -- The cycle length alone does not pin the polynomial down:
    -- several order 7 trinomials are primitive, so reading the wrong
    -- tap out of one can still give 127 bits. What does pin it down
    -- is the sequence itself, computed the other way round.
    -- nsl_data.prbs walks the polynomial as a mask over its state,
    -- where the generator walks it as a pair of depths into the bits
    -- it has already sent, so the two agree only if the depths were
    -- read off correctly.
    --
    -- The reference emits its seed before anything it computes, and
    -- the generator emits only what it computes, so the comparison
    -- starts one state's worth in.
    reference_v := prbs_bit_string(seed_c, prbs7, order_c + capture_c);

    for i in 0 to capture_c-1 loop
      assert bits_v(i) = reference_v(order_c + i)
        report "bit " & integer'image(i)
        & " of the pattern is " & std_ulogic'image(bits_v(i))
        & " where nsl_data.prbs makes it "
        & std_ulogic'image(reference_v(order_c + i))
        severity failure;
    end loop;

    log_info(ctxt, "emits the sequence nsl_data.prbs computes for the"
             & " same polynomial");

    done_s(0) <= '1';
    wait;
  end process;

  -- One byte per cycle, the width every 8b/10b lane in the library
  -- runs at, across the orders a transceiver offers. The shallowest
  -- and the deepest matter most: a checker only has eight bits of
  -- line per cycle, so a pattern of order 31 takes four of them
  -- before it has even seen enough history to predict anything.
  narrow_7: entity work.prbs_bench
    generic map(
      byte_count_c => 1,
      mode_c => PRBS_7,
      other_mode_c => PRBS_9,
      label_c => "1 byte prbs 7"
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      done_o => done_s(1)
      );

  narrow_31: entity work.prbs_bench
    generic map(
      byte_count_c => 1,
      mode_c => PRBS_31,
      other_mode_c => PRBS_23,
      label_c => "1 byte prbs 31"
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      done_o => done_s(2)
      );

  -- Wider than the pattern's own order, so a single word carries
  -- more history than the generator keeps.
  wide_7: entity work.prbs_bench
    generic map(
      byte_count_c => 4,
      mode_c => PRBS_7,
      other_mode_c => PRBS_15,
      label_c => "4 byte prbs 7"
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      done_o => done_s(3)
      );

  wide_23: entity work.prbs_bench
    generic map(
      byte_count_c => 4,
      mode_c => PRBS_23,
      other_mode_c => PRBS_31,
      label_c => "4 byte prbs 23"
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      done_o => done_s(4)
      );

  -- A transceiver that checks the pattern itself does not
  -- necessarily say whether it found it: the series 7 channel
  -- reports only the errors, so the answer the lane contract asks
  -- for has to be counted up from them.
  lock: block
    signal checking_s, restart_s, error_s, locked_s : std_ulogic;
  begin

    detector: nsl_transceiver.prbs.prbs_lock_detector
      generic map(
        lock_word_count_c => 16,
        unlock_word_count_c => 16
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        checking_i => checking_s,
        restart_i => restart_s,
        error_i => error_s,

        locked_o => locked_s
        );

    check: process
      constant ctxt : log_context := "lock detector";
      variable cycles_v : natural;

      procedure settle(count : natural) is
      begin
        for i in 0 to count-1 loop
          wait until rising_edge(clock_s);
        end loop;
      end procedure;
    begin
      done_s(5) <= '0';
      checking_s <= '0';
      restart_s <= '0';
      error_s <= '0';

      wait until reset_n_s = '1';

      -- Not looking is not the same as looking and failing.
      settle(64);
      assert locked_s = '0'
        report "the detector reported a pattern nobody was looking for"
        severity failure;

      wait until falling_edge(clock_s);
      checking_s <= '1';

      cycles_v := 0;
      while locked_s /= '1' loop
        wait until rising_edge(clock_s);
        cycles_v := cycles_v + 1;
        assert cycles_v < 256
          report "the detector never reported a clean stream"
          severity failure;
      end loop;

      log_info(ctxt, "called a clean stream locked after "
               & integer'image(cycles_v) & " words");

      -- One bad word out of many is a bit error, not a lost
      -- pattern: a detector that gave up on it would make a link
      -- with any error rate at all look unusable.
      wait until falling_edge(clock_s);
      error_s <= '1';
      wait until falling_edge(clock_s);
      error_s <= '0';

      settle(64);
      assert locked_s = '1'
        report "the detector gave up the pattern over one bad word"
        severity failure;

      log_info(ctxt, "kept the pattern across a single bad word");

      -- Nothing but bad words is a lost pattern.
      wait until falling_edge(clock_s);
      error_s <= '1';

      cycles_v := 0;
      while locked_s /= '0' loop
        wait until rising_edge(clock_s);
        cycles_v := cycles_v + 1;
        assert cycles_v < 256
          report "the detector kept the pattern through "
          & integer'image(cycles_v) & " unpredictable words"
          severity failure;
      end loop;

      log_info(ctxt, "gave the pattern up after "
               & integer'image(cycles_v) & " unpredictable words");

      -- And a restart drops it at once, which is what makes the
      -- answer trustworthy right after a counter window opens.
      wait until falling_edge(clock_s);
      error_s <= '0';
      settle(64);
      assert locked_s = '1'
        report "the detector did not come back on a clean stream"
        severity failure;

      wait until falling_edge(clock_s);
      restart_s <= '1';
      wait until rising_edge(clock_s);
      wait until rising_edge(clock_s);
      assert locked_s = '0'
        report "the detector still reported a pattern after a restart"
        severity failure;

      wait until falling_edge(clock_s);
      restart_s <= '0';

      log_info(ctxt, "dropped the pattern the moment it was restarted");

      done_s(5) <= '1';
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
