library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_clocking, nsl_time, nsl_simulation, nsl_math, work;
use nsl_math.timing.all;
use nsl_math.fixed.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;
use nsl_time.timestamp.all;
use nsl_time.discipline.all;

entity tb is
end tb;

architecture arch of tb is

  -- Synthetic time base: a second of timestamp time is a second of
  -- simulation time, but it is spent in 4000 cycles instead of the
  -- hundred million a real design would take, so a run of fifty pulses
  -- stays tractable.  The price is a coarse time base step, 250 us per
  -- cycle, which is the quantization of every offset the source
  -- reports and the yardstick every bound below is expressed in.
  constant clock_freq_c : real := 4.0e3;
  constant clock_period_c : time := seconds_to_time(1.0 / clock_freq_c);
  constant nominal_ns_c : real := 1.0e9 / clock_freq_c;
  constant step_ns_c : integer := 250000;

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 1);

  -- The resynchronizer, the pipeline of the source and the time base
  -- all answer a few cycles after the pulse, and nothing else moves in
  -- between, so this many cycles of watching catch every output a
  -- pulse can produce.
  constant watch_cycles_c : natural := 20;

  subtype inc_t is ufixed(18 downto -20);

  -- to_ufixed() of a real scales it through a VHDL integer, which
  -- overflows at this many bits.
  function to_inc(value : real) return inc_t
  is
    variable ret : inc_t;
    variable acc : real;
  begin
    ret := (others => '0');
    acc := value;
    for i in inc_t'left downto inc_t'right loop
      if acc >= 2.0 ** i then
        ret(i) := '1';
        acc := acc - 2.0 ** i;
      end if;
    end loop;
    return ret;
  end function;

  constant inc_nominal_c : inc_t := to_inc(nominal_ns_c);

  -- Alignment, gating and tick scenarios.  The time base runs at its
  -- nominal rate; only the phase is wrong, and only the source can
  -- put it back.
  constant a_threshold_c : natural := 2000000;
  -- A reference second 37 ppm longer than a simulation second, so the
  -- pulse walks across the clock period over the run and the
  -- resynchronizer latency is not always the same number of cycles.
  constant a_period_c : time := 1 sec + 37 us;
  -- Neither delay is a whole number of clock periods: the pulse edge
  -- lands inside a cycle, which is the whole point of resynchronizing.
  constant a_ahead_delay_c : time := 200137 us;
  constant a_behind_delay_c : time := 800137 us;
  -- A pulse measured right after an alignment reads the phase the
  -- alignment left, plus what the pulse walked since, plus the cycle
  -- the sample was rounded to.
  constant a_residual_bound_c : integer := 3 * step_ns_c;

  signal a_pps_s, a_enable_s : std_ulogic;
  signal a_force_s, a_time_s : timestamp_t;
  signal a_force_set_s : std_ulogic;
  signal a_offset_s, a_adj_s : timestamp_nanosecond_offset_t;
  signal a_offset_valid_s, a_adj_valid_s, a_tick_s : std_ulogic;

  -- Closed loop: pps_source, servo, clock driver and time base, all on
  -- the same clock.  The reference second is 200 ppm longer than a
  -- simulation second and the time base is seeded 800 ppm fast, so the
  -- local clock gains about a millisecond per reference second and the
  -- servo has to settle near -1e6 ppb.
  constant b_threshold_c : natural := 5000000;
  constant b_period_c : time := 1 sec + 200 us;
  constant b_first_delay_c : time := 100211 us;
  constant b_error_ppm_c : real := 800.0e-6;
  constant inc_error_c : inc_t := to_inc(nominal_ns_c * b_error_ppm_c);

  -- A proportional gain of 1/2 and an integral gain of 1/16 per one
  -- second measurement period put both poles of the loop at 0.75, so
  -- thirty periods take the transient far below the time base step.
  constant b_kp_l2_c : natural := 1;
  constant b_ki_l2_c : natural := 4;
  constant b_clamp_ppb_c : natural := 3000000;

  constant b_settle_count_c : natural := 30;
  constant b_check_count_c : natural := 20;
  -- Once the frequency error is gone the loop is only fighting the
  -- quantization of its own measurement: the phase walks by less than
  -- a step per period and the reported offset hops between the couple
  -- of steps around zero.
  constant b_residual_bound_c : integer := 3 * step_ns_c;
  constant b_expected_ppb_c : integer := -999960;
  constant b_ppb_tolerance_c : integer := 150000;

  signal b_pps_s : std_ulogic;
  signal b_force_s, b_time_s : timestamp_t;
  signal b_force_set_s : std_ulogic;
  signal b_offset_s, b_adj_s : timestamp_nanosecond_offset_t;
  signal b_offset_valid_s, b_adj_valid_s, b_tick_s : std_ulogic;
  signal b_ppb_s : frequency_ppb_t;
  signal b_drv_inc_s, b_inc_s : inc_t;

begin

  -- Scenarios 1, 3 and 4: a time base put out of phase on purpose, in
  -- both directions, then gated off and back on.
  align_test: process is
    constant ctxt : log_context := "align";
    variable ticks, offs, adjs : integer;
    variable offset_v, adj_v : integer;

    procedure set_phase(constant sec : in integer;
                        constant ns : in integer) is
    begin
      wait until falling_edge(clock_s);
      a_force_s.second <= to_unsigned(sec, a_force_s.second'length);
      a_force_s.nanosecond <= to_unsigned(ns, a_force_s.nanosecond'length);
      a_force_set_s <= '1';
      wait until falling_edge(clock_s);
      a_force_set_s <= '0';
      a_force_s.second <= (others => '-');
      a_force_s.nanosecond <= (others => '-');
    end procedure;

    -- Raises the pulse at whatever time the process stands at, counts
    -- everything the source emits over the reaction window, then holds
    -- the line low for the rest of the period.
    procedure pps(constant period : in time) is
      variable t0 : time;
    begin
      ticks := 0;
      offs := 0;
      adjs := 0;
      offset_v := 0;
      adj_v := 0;

      t0 := now;
      a_pps_s <= '1';
      for i in 1 to watch_cycles_c loop
        wait until rising_edge(clock_s);
        if a_tick_s = '1' then
          ticks := ticks + 1;
        end if;
        if a_offset_valid_s = '1' then
          offs := offs + 1;
          offset_v := to_integer(a_offset_s);
        end if;
        if a_adj_valid_s = '1' then
          adjs := adjs + 1;
          adj_v := to_integer(a_adj_s);
        end if;
      end loop;
      wait for clock_period_c / 3;
      a_pps_s <= '0';
      wait for period - (now - t0);
    end procedure;

    procedure check_measurement(constant what : in string) is
    begin
      assert_equal(ctxt, what & ", ticks", ticks, 1, failure);
      assert_equal(ctxt, what & ", offsets", offs, 1, failure);
      assert_equal(ctxt, what & ", adjustments", adjs, 0, failure);
      assert abs(offset_v) <= a_residual_bound_c
        report what & ": offset " & integer'image(offset_v)
        & " ns, past the residual an aligned time base can show"
        severity failure;
    end procedure;

    procedure check_adjustment(constant what : in string;
                               constant low : in integer;
                               constant high : in integer) is
    begin
      assert_equal(ctxt, what & ", ticks", ticks, 1, failure);
      assert_equal(ctxt, what & ", offsets", offs, 0, failure);
      assert_equal(ctxt, what & ", adjustments", adjs, 1, failure);
      assert low <= adj_v and adj_v <= high
        report what & ": adjustment " & integer'image(adj_v)
        & " ns is not what lands the time base on the boundary"
        severity failure;
    end procedure;
  begin
    done_s(0) <= '0';
    a_pps_s <= '0';
    a_enable_s <= '1';
    a_force_set_s <= '0';
    a_force_s.abs_change <= '0';
    a_force_s.second <= (others => '-');
    a_force_s.nanosecond <= (others => '-');

    wait until reset_n_s = '1';
    wait for clock_period_c * 4;

    -- Local clock ahead of the pulse by a fifth of a second.  The
    -- source has to ask for that much of a step back.
    set_phase(10, 0);
    wait for a_ahead_delay_c;
    pps(a_period_c);
    check_adjustment("ahead by 200 ms", -210000000, -195000000);
    log_info(ctxt, "step back: " & integer'image(adj_v) & " ns");

    pps(a_period_c);
    check_measurement("first pulse after step back");
    log_info(ctxt, "offset after step back: " & integer'image(offset_v)
             & " ns");

    pps(a_period_c);
    check_measurement("second pulse after step back");

    -- Local clock behind the pulse by a fifth of a second, which the
    -- nanosecond field shows as eight tenths of a second: only the
    -- fold onto the nearest boundary turns that into a small step
    -- forward.
    set_phase(10, 0);
    wait for a_behind_delay_c;
    pps(a_period_c);
    check_adjustment("behind by 200 ms", 190000000, 205000000);
    log_info(ctxt, "step forward: " & integer'image(adj_v) & " ns");

    pps(a_period_c);
    check_measurement("first pulse after step forward");
    log_info(ctxt, "offset after step forward: " & integer'image(offset_v)
             & " ns");

    -- Gating: the pulses keep coming and nothing comes out, not even
    -- the tick.
    wait until falling_edge(clock_s);
    a_enable_s <= '0';

    for i in 1 to 2 loop
      pps(a_period_c);
      assert_equal(ctxt, "ticks while disabled", ticks, 0, failure);
      assert_equal(ctxt, "offsets while disabled", offs, 0, failure);
      assert_equal(ctxt, "adjustments while disabled", adjs, 0, failure);
    end loop;

    wait until falling_edge(clock_s);
    a_enable_s <= '1';

    pps(a_period_c);
    check_measurement("first pulse after re-enable");
    log_info(ctxt, "offset after re-enable: " & integer'image(offset_v)
             & " ns");

    log_info(ctxt, "alignment and gating done");
    done_s(0) <= '1';
    wait;
  end process;

  a_dut: nsl_time.discipline.discipline_pps_source
    generic map(
      align_threshold_ns_c => a_threshold_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      enable_i => a_enable_s,
      pps_i => a_pps_s,
      timestamp_i => a_time_s,
      offset_o => a_offset_s,
      offset_valid_o => a_offset_valid_s,
      adj_o => a_adj_s,
      adj_valid_o => a_adj_valid_s,
      tick_o => a_tick_s
      );

  a_clock: nsl_time.clock.clock_adjustable
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      sub_nanosecond_inc_i => inc_nominal_c,
      nanosecond_adj_i => a_adj_s,
      nanosecond_adj_set_i => a_adj_valid_s,
      timestamp_i => a_force_s,
      timestamp_set_i => a_force_set_s,
      timestamp_o => a_time_s
      );

  -- Scenario 2: the source is the only thing telling the loop where
  -- the second is.
  loop_test: process is
    constant ctxt : log_context := "loop";
    variable ticks, offs, adjs : integer;
    variable offset_v, adj_v, true_v : integer;
    variable worst, low, high, sum : integer;

    procedure set_phase(constant sec : in integer;
                        constant ns : in integer) is
    begin
      wait until falling_edge(clock_s);
      b_force_s.second <= to_unsigned(sec, b_force_s.second'length);
      b_force_s.nanosecond <= to_unsigned(ns, b_force_s.nanosecond'length);
      b_force_set_s <= '1';
      wait until falling_edge(clock_s);
      b_force_set_s <= '0';
      b_force_s.second <= (others => '-');
      b_force_s.nanosecond <= (others => '-');
    end procedure;

    procedure pps(constant period : in time) is
      variable t0 : time;
    begin
      ticks := 0;
      offs := 0;
      adjs := 0;
      offset_v := 0;
      adj_v := 0;

      t0 := now;
      -- Read at the very instant of the pulse, this is the phase error
      -- the source cannot see: it only ever samples the time base a
      -- few cycles later, and reports what it read there.
      true_v := to_integer(b_time_s.nanosecond);
      if true_v >= 500000000 then
        true_v := true_v - 1000000000;
      end if;

      b_pps_s <= '1';
      for i in 1 to watch_cycles_c loop
        wait until rising_edge(clock_s);
        if b_tick_s = '1' then
          ticks := ticks + 1;
        end if;
        if b_offset_valid_s = '1' then
          offs := offs + 1;
          offset_v := to_integer(b_offset_s);
        end if;
        if b_adj_valid_s = '1' then
          adjs := adjs + 1;
          adj_v := to_integer(b_adj_s);
        end if;
      end loop;
      wait for clock_period_c / 3;
      b_pps_s <= '0';
      wait for period - (now - t0);
    end procedure;
  begin
    done_s(1) <= '0';
    b_pps_s <= '0';
    b_force_set_s <= '0';
    b_force_s.abs_change <= '0';
    b_force_s.second <= (others => '-');
    b_force_s.nanosecond <= (others => '-');

    wait until reset_n_s = '1';
    wait for clock_period_c * 4;

    -- A tenth of a second of phase error on top of the frequency
    -- error, so the run starts on the alignment path.
    set_phase(100, 0);
    wait for b_first_delay_c;
    pps(b_period_c);
    assert_equal(ctxt, "first pulse adjustments", adjs, 1, failure);
    assert_equal(ctxt, "first pulse offsets", offs, 0, failure);
    log_info(ctxt, "acquisition step: " & integer'image(adj_v) & " ns");

    worst := 0;
    for i in 1 to b_settle_count_c loop
      pps(b_period_c);
      if offs = 1 and abs(offset_v) > worst then
        worst := abs(offset_v);
      end if;
    end loop;
    log_info(ctxt, "peak offset during acquisition: "
             & integer'image(worst) & " ns");

    low := integer'high;
    high := integer'low;
    sum := 0;
    for i in 1 to b_check_count_c loop
      pps(b_period_c);
      assert_equal(ctxt, "ticks", ticks, 1, failure);
      assert_equal(ctxt, "offsets", offs, 1, failure);
      assert_equal(ctxt, "adjustments", adjs, 0, failure);
      assert abs(offset_v) <= b_residual_bound_c
        report "Offset " & integer'image(offset_v)
        & " ns is past the residual bound at measurement "
        & integer'image(i)
        severity failure;
      if offset_v < low then
        low := offset_v;
      end if;
      if offset_v > high then
        high := offset_v;
      end if;
      sum := sum + offset_v;
    end loop;

    log_info(ctxt, "residual offset: mean " & integer'image(sum / b_check_count_c)
             & " ns, from " & integer'image(low) & " to "
             & integer'image(high) & " ns, "
             & integer'image((high - low) / step_ns_c)
             & " time base steps of spread");
    log_info(ctxt, "phase error the loop cannot see: "
             & integer'image(true_v) & " ns, "
             & integer'image(-true_v / step_ns_c)
             & " cycles of resynchronizer latency");
    log_info(ctxt, "correction: " & integer'image(to_integer(b_ppb_s))
             & " ppb");

    -- The loop converged if it holds, not if one sample lands on zero:
    -- the measurement is quantized to a time base step, so what is
    -- asserted is that the whole check window stays inside a couple of
    -- steps of itself.
    assert high - low <= 2 * step_ns_c
      report "Offset spans " & integer'image(high - low)
      & " ns over the check window, the loop is not settled"
      severity failure;

    assert abs(to_integer(b_ppb_s) - b_expected_ppb_c) <= b_ppb_tolerance_c
      report "Correction " & integer'image(to_integer(b_ppb_s))
      & " ppb does not match the seeded frequency error"
      severity failure;

    log_info(ctxt, "closed loop done");
    done_s(1) <= '1';
    wait;
  end process;

  b_dut: nsl_time.discipline.discipline_pps_source
    generic map(
      align_threshold_ns_c => b_threshold_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      enable_i => '1',
      pps_i => b_pps_s,
      timestamp_i => b_time_s,
      offset_o => b_offset_s,
      offset_valid_o => b_offset_valid_s,
      adj_o => b_adj_s,
      adj_valid_o => b_adj_valid_s,
      tick_o => b_tick_s
      );

  b_servo: nsl_time.discipline.discipline_pi_servo
    generic map(
      kp_l2_c => b_kp_l2_c,
      ki_l2_c => b_ki_l2_c,
      freq_clamp_ppb_c => b_clamp_ppb_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      offset_i => b_offset_s,
      offset_valid_i => b_offset_valid_s,
      freq_offset_ppb_o => b_ppb_s
      );

  b_driver: nsl_time.discipline.discipline_clock_driver
    generic map(
      clock_hz_c => integer(clock_freq_c)
      )
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,
      freq_offset_ppb_i => b_ppb_s,
      rtc_clock_i => clock_s,
      sub_nanosecond_inc_o => b_drv_inc_s
      );

  b_inc_s <= b_drv_inc_s + inc_error_c;

  b_clock: nsl_time.clock.clock_adjustable
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      sub_nanosecond_inc_i => b_inc_s,
      nanosecond_adj_i => b_adj_s,
      nanosecond_adj_set_i => b_adj_valid_s,
      timestamp_i => b_force_s,
      timestamp_set_i => b_force_set_s,
      timestamp_o => b_time_s
      );

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => clock_period_c,
      reset_duration(0) => clock_period_c * 3,
      reset_n_o(0) => reset_n_s,
      clock_o(0) => clock_s,
      done_i => done_s
      );

end;
