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
  signal done_s : std_ulogic_vector(0 to 2);

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

  -- Naming: a pps_source owning the phase, a second setter naming the
  -- seconds and the time base taking both.  The reference second is
  -- 5 ms longer than a simulation second, so the source realigns at
  -- every pulse and the time base always crosses the boundary a few
  -- milliseconds before the tick: the nanosecond field read at the
  -- tick is far from zero, which is what tells a kept nanosecond
  -- field apart from a zeroed one.
  constant c_threshold_c : natural := 2000000;
  constant c_period_c : time := 1 sec + 5 ms;
  constant c_first_delay_c : time := 200137 us;
  -- Where the guard phase parks the nanosecond field, past the
  -- quarter second the setter refuses to name across.
  constant c_guard_ns_c : integer := 400000000;
  constant c_guard_bound_c : integer := 250000000;
  -- Whatever the time base counts from, it is not the timescale the
  -- time-of-day model speaks.
  constant c_wrong_second_c : integer := 7;
  constant c_epoch_base_c : integer := 1000;

  signal c_pps_s : std_ulogic;
  signal c_align_en_s, c_enable_s : std_ulogic;
  signal c_time_s, c_force_s : timestamp_t;
  signal c_force_set_s : std_ulogic;
  signal c_adj_s : timestamp_nanosecond_offset_t;
  signal c_adj_valid_s, c_adj_gated_s, c_tick_s : std_ulogic;
  signal c_second_s : unsigned(31 downto 0);
  signal c_second_valid_s : std_ulogic;
  signal c_set_ts_s, c_clock_ts_s : timestamp_t;
  signal c_set_valid_s, c_clock_set_s : std_ulogic;

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

  -- Scenario 5: naming the seconds of a clock the source already keeps
  -- in phase.  The bench plays the time-of-day source of a receiver:
  -- shortly after each pulse it says which second the epoch that pulse
  -- opened carries, and the setter has to make the time base agree.
  naming_test: process is
    constant ctxt : log_context := "naming";
    variable epoch : integer;
    variable ticks, sets : integer;
    variable ns_at_tick, sec_at_tick : integer;
    variable set_ns, set_second : integer;
    variable set_abs : std_ulogic;

    procedure set_phase(constant sec : in integer;
                        constant ns : in integer) is
    begin
      wait until falling_edge(clock_s);
      c_force_s.second <= to_unsigned(sec, c_force_s.second'length);
      c_force_s.nanosecond <= to_unsigned(ns, c_force_s.nanosecond'length);
      c_force_set_s <= '1';
      wait until falling_edge(clock_s);
      c_force_set_s <= '0';
      c_force_s.second <= (others => '-');
      c_force_s.nanosecond <= (others => '-');
    end procedure;

    -- The time-of-day message of a receiver: it names the second the
    -- pulse just opened, so it can only be sent once the pulse is
    -- gone.
    procedure tod(constant sec : in integer) is
    begin
      wait until falling_edge(clock_s);
      c_second_s <= to_unsigned(sec, c_second_s'length);
      c_second_valid_s <= '1';
      wait until falling_edge(clock_s);
      c_second_valid_s <= '0';
      c_second_s <= (others => '-');
    end procedure;

    procedure pps(constant labelled : in boolean) is
      variable t0 : time;
    begin
      ticks := 0;
      sets := 0;
      ns_at_tick := -1;
      sec_at_tick := -1;
      set_ns := -1;
      set_second := -1;
      set_abs := '0';
      epoch := epoch + 1;

      t0 := now;
      c_pps_s <= '1';
      for i in 1 to watch_cycles_c loop
        wait until rising_edge(clock_s);
        if c_tick_s = '1' then
          ticks := ticks + 1;
          ns_at_tick := to_integer(c_time_s.nanosecond);
          sec_at_tick := to_integer(c_time_s.second);
        end if;
        if c_set_valid_s = '1' then
          sets := sets + 1;
          set_ns := to_integer(c_set_ts_s.nanosecond);
          set_second := to_integer(c_set_ts_s.second);
          set_abs := c_set_ts_s.abs_change;
        end if;
      end loop;
      wait for clock_period_c / 3;
      c_pps_s <= '0';
      if labelled then
        tod(epoch);
      end if;
      wait for c_period_c - (now - t0);
    end procedure;

    procedure check_quiet(constant what : in string) is
    begin
      assert_equal(ctxt, what & ", ticks", ticks, 1, failure);
      assert_equal(ctxt, what & ", sets", sets, 0, failure);
    end procedure;

    procedure check_set(constant what : in string) is
    begin
      assert_equal(ctxt, what & ", ticks", ticks, 1, failure);
      assert_equal(ctxt, what & ", sets", sets, 1, failure);
      assert_equal(ctxt, what & ", second named", set_second, epoch, failure);
      assert_equal(ctxt, what & ", nanosecond kept", set_ns, ns_at_tick,
                   failure);
      assert_equal(ctxt, what & ", absolute change", set_abs, '1', failure);
      assert ns_at_tick > step_ns_c
        report what & ": the time base was only "
        & integer'image(ns_at_tick)
        & " ns past the boundary, too close to tell a kept nanosecond"
        & " field from a zeroed one"
        severity failure;
    end procedure;

    -- Quiet because the time base already carries the name it would
    -- have been given.
    procedure check_named(constant what : in string) is
    begin
      check_quiet(what);
      assert_equal(ctxt, what & ", second at tick", sec_at_tick, epoch,
                   failure);
    end procedure;

    -- Quiet although the name is wrong and nothing but the guard could
    -- excuse it.
    procedure check_unnamed(constant what : in string) is
    begin
      check_quiet(what);
      assert sec_at_tick /= epoch
        report what & ": the time base already reads second "
        & integer'image(epoch) & ", there is nothing left to name"
        severity failure;
      assert ns_at_tick < c_guard_bound_c
        report what & ": the time base stood " & integer'image(ns_at_tick)
        & " ns into the second, the guard is what kept the setter quiet"
        severity failure;
    end procedure;

    -- Quiet because the nanosecond field says the second field cannot
    -- be trusted.
    procedure check_guarded(constant what : in string) is
    begin
      check_quiet(what);
      assert sec_at_tick /= epoch
        report what & ": the time base already reads second "
        & integer'image(epoch) & ", there is nothing left to name"
        severity failure;
      assert ns_at_tick > c_guard_bound_c
        report what & ": the time base stood only "
        & integer'image(ns_at_tick)
        & " ns into the second, the guard is not what is being tested"
        severity failure;
    end procedure;
  begin
    done_s(2) <= '0';
    epoch := c_epoch_base_c;
    c_pps_s <= '0';
    c_align_en_s <= '1';
    c_enable_s <= '1';
    c_force_set_s <= '0';
    c_force_s.abs_change <= '1';
    c_force_s.second <= (others => '-');
    c_force_s.nanosecond <= (others => '-');
    c_second_s <= (others => '-');
    c_second_valid_s <= '0';

    wait until reset_n_s = '1';
    wait for clock_period_c * 4;

    -- A time base counting from an unrelated second, a fifth of a
    -- second out of phase: the source has the phase back on the first
    -- pulse, the second stays wrong until something names it.
    set_phase(c_wrong_second_c, 0);
    wait for c_first_delay_c;

    pps(false);
    check_quiet("acquisition pulse");

    pps(true);
    check_unnamed("first labelled pulse");

    pps(true);
    check_set("first armed tick");
    log_info(ctxt, "named second " & integer'image(set_second)
             & " with the time base " & integer'image(set_ns)
             & " ns into it");

    pps(true);
    check_named("first pulse after naming");
    pps(true);
    check_named("second pulse after naming");

    -- With the phase adjustments held off the time base is left deep
    -- in the second at the tick, where the second field it shows says
    -- nothing about which side of the boundary it stands on.
    wait until falling_edge(clock_s);
    c_align_en_s <= '0';
    set_phase(c_wrong_second_c, c_guard_ns_c);

    pps(true);
    check_guarded("labelled tick past the guard");
    pps(false);
    check_guarded("second tick past the guard");

    wait until falling_edge(clock_s);
    c_align_en_s <= '1';

    pps(false);
    check_quiet("realignment pulse");

    -- The time-of-day source went silent: the ticks keep coming, the
    -- second stays wrong, and the setter has nothing to say.
    pps(false);
    check_unnamed("first pulse without a label");
    pps(false);
    check_unnamed("second pulse without a label");

    pps(true);
    check_unnamed("pulse arming before gating");

    wait until falling_edge(clock_s);
    c_enable_s <= '0';
    pps(false);
    check_unnamed("armed tick while disabled");

    wait until falling_edge(clock_s);
    c_enable_s <= '1';
    pps(false);
    check_unnamed("first pulse after re-enable");

    pps(true);
    check_unnamed("pulse arming after re-enable");
    pps(true);
    check_set("first armed tick after re-enable");
    log_info(ctxt, "named second " & integer'image(set_second)
             & " with the time base " & integer'image(set_ns)
             & " ns into it");

    pps(true);
    check_named("pulse after the second naming");

    log_info(ctxt, "second naming done");
    done_s(2) <= '1';
    wait;
  end process;

  c_source: nsl_time.discipline.discipline_pps_source
    generic map(
      align_threshold_ns_c => c_threshold_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      enable_i => '1',
      pps_i => c_pps_s,
      timestamp_i => c_time_s,
      offset_o => open,
      offset_valid_o => open,
      adj_o => c_adj_s,
      adj_valid_o => c_adj_valid_s,
      tick_o => c_tick_s
      );

  c_adj_gated_s <= c_adj_valid_s and c_align_en_s;

  c_dut: nsl_time.discipline.discipline_second_setter
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      enable_i => c_enable_s,
      second_i => c_second_s,
      second_valid_i => c_second_valid_s,
      tick_i => c_tick_s,
      timestamp_i => c_time_s,
      timestamp_o => c_set_ts_s,
      timestamp_set_o => c_set_valid_s
      );

  -- The bench seeds the time base the same way the setter names it,
  -- and only when the setter is not talking.
  c_clock_ts_s <= c_force_s when c_force_set_s = '1' else c_set_ts_s;
  c_clock_set_s <= c_force_set_s or c_set_valid_s;

  c_clock: nsl_time.clock.clock_adjustable
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      sub_nanosecond_inc_i => inc_nominal_c,
      nanosecond_adj_i => c_adj_s,
      nanosecond_adj_set_i => c_adj_gated_s,
      timestamp_i => c_clock_ts_s,
      timestamp_set_i => c_clock_set_s,
      timestamp_o => c_time_s
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
