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

  -- The servo gains fold the measurement period in: a shift-only
  -- proportional gain of 2**-kp is only stabilizing when a part per
  -- billion of correction moves the offset by about a nanosecond over
  -- one measurement period, which happens when the period is a
  -- fraction of a second.  Simulating enough of those periods to see
  -- the loop converge is only tractable with a slow clock, so the
  -- closed loop below runs a 10 kHz clock and measures every 2500
  -- cycles.
  constant clock_freq_c : real := 1.0e4;
  constant clock_period_c : time := seconds_to_time(1.0 / clock_freq_c);
  constant nominal_ns_c : real := 1.0e9 / clock_freq_c;

  -- Time base clock of the multi-domain scenarios.  Its period shares
  -- no more than a few picoseconds with the servo clock period, so the
  -- phase between the two domains never repeats over the run.
  constant rtc_hz_c : natural := 13337;
  constant rtc_period_c : time := seconds_to_time(1.0 / real(rtc_hz_c));
  constant rtc_nominal_ns_c : real := 1.0e9 / real(rtc_hz_c);

  signal clock_s, rtc_clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 7);

  -- Servo unit test
  constant servo_kp_l2_c : natural := 2;
  constant servo_ki_l2_c : natural := 6;
  constant servo_clamp_c : natural := 100000;

  signal su_offset_s : timestamp_nanosecond_offset_t;
  signal su_valid_s, su_clear_s : std_ulogic;
  signal su_ppb_s : frequency_ppb_t;

  -- DAC driver unit test
  constant dac_width_c : natural := 16;
  signal du_ppb_s : frequency_ppb_t;
  signal du_a_code_s, du_b_code_s : unsigned(dac_width_c-1 downto 0);
  signal du_a_changed_s, du_b_changed_s : std_ulogic;

  -- Clock driver unit test, on a clock fast enough for the increment
  -- to fit the range to_real() can handle.
  constant cu_clock_hz_c : natural := 100000000;
  constant cu_nominal_ns_c : real := 1.0e9 / real(cu_clock_hz_c);
  signal cu_ppb_s : frequency_ppb_t;
  signal cu_inc_s : ufixed(4 downto -20);

  -- Closed loop
  subtype inc_t is ufixed(17 downto -20);

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
  -- Deliberate +50 ppm of the disciplined oscillator.
  constant inc_error_c : inc_t := to_inc(nominal_ns_c * 50.0e-6);
  constant initial_offset_ns_c : integer := 2000;

  constant meas_period_c : natural := 2500;
  constant settle_period_count_c : natural := 90;
  constant check_period_count_c : natural := 40;
  -- The integrator keeps fractional bits, so nothing but the
  -- nanosecond of measurement quantization is left once converged.
  constant loop_kp_l2_c : natural := 0;
  constant loop_ki_l2_c : natural := 3;
  constant residual_bound_ns_c : integer := 2;

  signal ref_time_s, disc_time_s : timestamp_t;
  signal ref_force_s, disc_force_s : timestamp_t;
  signal force_set_s : std_ulogic;
  signal drv_inc_s, disc_inc_s : inc_t;
  signal loop_offset_s : timestamp_nanosecond_offset_t;
  signal loop_valid_s, loop_run_s : std_ulogic;
  signal loop_ppb_s : frequency_ppb_t;

  -- Multi-domain closed loop.  The servo, the reference time base and
  -- the command side of the driver run on clock_s; the disciplined
  -- time base, the driver output and the skew measurement run on
  -- rtc_clock_s.
  constant minc_nominal_c : inc_t := to_inc(rtc_nominal_ns_c);
  constant minc_error_c : inc_t := to_inc(rtc_nominal_ns_c * 50.0e-6);
  -- 3334 cycles of the time base clock is the same quarter of a second
  -- the single-domain loop measures over, which is what the gains are
  -- tuned for.
  constant mmeas_period_c : natural := 3334;
  constant minitial_offset_ns_c : integer := 300000;
  constant msettle_period_count_c : natural := 90;
  constant mcheck_period_count_c : natural := 40;
  -- The reference time base only steps once per servo clock period, so
  -- a measurement taken on a time base edge reads a reference that is
  -- stale by anything from zero to one such period, uniformly.  The
  -- loop drives the mean measured offset to zero, which parks the true
  -- offset around minus half a period; the measured offset then covers
  -- the staleness itself, plus what the proportional term makes of
  -- that dither, which a gain of T/2**kp = 0.25 damps to about a
  -- quarter of it.  That is one and a quarter servo clock period,
  -- 125 us; the bound keeps a little more.
  constant mresidual_bound_ns_c : integer := 150000;

  signal mref_time_s, mdisc_time_s : timestamp_t;
  signal mref_force_s, mdisc_force_s : timestamp_t;
  signal mforce_set_s : std_ulogic;
  signal mdrv_inc_s, mdisc_inc_s : inc_t;
  signal mmeas_offset_s : timestamp_nanosecond_offset_t;
  signal mmeas_strobe_s, mstrobe_s, mloop_run_s : std_ulogic;
  signal mfilt_offset_s : timestamp_nanosecond_offset_t;
  signal mfilt_valid_s : std_ulogic;
  signal mservo_offset_slv_s
    : std_ulogic_vector(timestamp_nanosecond_offset_t'length-1 downto 0);
  signal mservo_offset_s : timestamp_nanosecond_offset_t;
  signal mservo_valid_s : std_ulogic;
  signal mloop_ppb_s : frequency_ppb_t;

  -- Step applier tests.  The time base the applier reads is synthetic:
  -- a plain counter stepping by a known amount per cycle, so the
  -- expected result and the lag are both exact.
  constant applier_step_ns_c : integer := 1000;
  constant applier_start_sec_c : integer := 1000;
  constant applier_start_ns_c : integer := 500000000;

  signal au_ts_s, au_ref_s, au_sync_s, au_out_s : timestamp_t;
  signal au_valid_s, au_set_s : std_ulogic;

  signal ax_ts_s, ax_ref_s, ax_sync_s, ax_out_s : timestamp_t;
  signal ax_valid_s, ax_set_s : std_ulogic;

  -- Clock driver coherence test
  constant tu_ppb_c : integer := 16#555555#;
  constant tu_transition_count_c : natural := 12;
  -- 24 steps fit well inside a servo clock period, and the time base
  -- clock ticks several times inside the window.
  constant tu_bit_skew_c : time := 1600 ns;

  signal tu_ppb_s : frequency_ppb_t;
  signal tu_inc_s, tu_low_inc_s, tu_high_inc_s : inc_t;
  signal tu_arm_s : std_ulogic;

  type ts_delta_t is
  record
    sec : integer;
    ns : integer;
  end record;

  function ts_sub(a, b : timestamp_t) return ts_delta_t
  is
    variable ret : ts_delta_t;
  begin
    ret.sec := to_integer(a.second) - to_integer(b.second);
    ret.ns := to_integer(a.nanosecond) - to_integer(b.nanosecond);
    if ret.ns < 0 then
      ret.ns := ret.ns + 1000000000;
      ret.sec := ret.sec - 1;
    end if;
    return ret;
  end function;

  function ts_add(a : timestamp_t; d : ts_delta_t) return timestamp_t
  is
    variable sec, ns : integer;
  begin
    sec := to_integer(a.second) + d.sec;
    ns := to_integer(a.nanosecond) + d.ns;
    if ns >= 1000000000 then
      ns := ns - 1000000000;
      sec := sec + 1;
    end if;
    return (abs_change => '0',
            second => to_unsigned(sec, timestamp_second_t'length),
            nanosecond => to_unsigned(ns, timestamp_nanosecond_t'length));
  end function;

  -- Difference of two timestamps known to be less than a second apart.
  function ts_diff_ns(a, b : timestamp_t) return integer
  is
    constant d : ts_delta_t := ts_sub(a, b);
  begin
    assert d.sec = 0 or d.sec = -1
      report "Timestamps are more than a second apart"
      severity failure;

    if d.sec = 0 then
      return d.ns;
    end if;

    return d.ns - 1000000000;
  end function;

  -- Hands one step command over and checks where it lands.  The
  -- applier is asked for reference + (local time - sync), so the
  -- result is compared against the local time read at the very cycle
  -- the set pulse is seen.
  procedure applier_case(
    constant ctxt : in log_context;
    constant what : in string;
    constant reference : in timestamp_t;
    constant sync : in timestamp_t;
    signal cmd_clock : in std_ulogic;
    signal rtc_clock : in std_ulogic;
    signal reference_o : out timestamp_t;
    signal sync_o : out timestamp_t;
    signal valid_o : out std_ulogic;
    signal ts_i : in timestamp_t;
    signal result_i : in timestamp_t;
    signal set_i : in std_ulogic)
  is
    variable now_v, got_v, expected_v : timestamp_t;
    variable pulses, err : integer;
  begin
    pulses := 0;
    got_v := timestamp_zero_c;
    now_v := timestamp_zero_c;

    wait until falling_edge(cmd_clock);
    reference_o <= reference;
    sync_o <= sync;
    valid_o <= '1';
    wait until falling_edge(cmd_clock);
    valid_o <= '0';

    for i in 1 to 60 loop
      wait until rising_edge(rtc_clock);
      if set_i = '1' then
        now_v := ts_i;
        got_v := result_i;
        pulses := pulses + 1;
      end if;
    end loop;

    assert_equal(ctxt, what & ", set pulses", pulses, 1, failure);
    assert_equal(ctxt, what & ", abs_change", got_v.abs_change, '1', failure);

    expected_v := ts_add(reference, ts_sub(now_v, sync));
    err := ts_diff_ns(expected_v, got_v);
    log_info(ctxt, what & ": lag " & integer'image(err) & " ns, "
             & integer'image(err / applier_step_ns_c) & " time base cycles");

    -- The applier reads the local time one cycle before it normalizes
    -- and two before the time base takes the set, so the step is
    -- expected to land a constant three cycles of the time base clock
    -- late.  Anything else, and in particular anything that ignores
    -- the elapsed time, is out of that window.
    assert err >= 0 and err <= 3 * applier_step_ns_c
      report what & ": step landed " & integer'image(err)
      & " ns off, past the lag the applier documents"
      severity failure;
  end procedure;

begin

  servo_unit: process is
    constant ctxt : log_context := "servo";

    procedure pulse(offset : integer) is
    begin
      wait until falling_edge(clock_s);
      su_offset_s <= to_signed(offset, su_offset_s'length);
      su_valid_s <= '1';
      wait until falling_edge(clock_s);
      su_valid_s <= '0';
      su_offset_s <= (others => '-');
      for i in 1 to 4 loop
        wait until falling_edge(clock_s);
      end loop;
    end procedure;

    procedure clear is
    begin
      wait until falling_edge(clock_s);
      su_clear_s <= '1';
      wait until falling_edge(clock_s);
      su_clear_s <= '0';
      wait until falling_edge(clock_s);
    end procedure;

    procedure check(what : string; expected : integer) is
    begin
      assert_equal(ctxt, what, to_integer(su_ppb_s), expected, failure);
    end procedure;
  begin
    done_s(0) <= '0';
    su_offset_s <= (others => '-');
    su_valid_s <= '0';
    su_clear_s <= '0';

    wait until reset_n_s = '1';
    wait for clock_period_c * 4;
    check("idle output", 0);

    -- Local ahead of reference asks for a slower clock.  P is
    -- -1024/4, I accumulates -1024/64 per measurement.
    pulse(1024);
    check("first proportional and integral", -272);
    pulse(1024);
    check("integral accumulation", -288);
    pulse(0);
    check("integrator holds without offset", -32);

    clear;
    check("cleared output", 0);
    pulse(1024);
    check("integrator emptied by clear", -272);

    clear;
    pulse(-1024);
    check("reversed sign", 272);

    -- 1e8 ns of offset asks for 25e6 ppb of proportional term and
    -- 1562500 ppb of integral step, both far past the clamp.
    clear;
    pulse(100000000);
    check("output clamp", -servo_clamp_c);
    for i in 1 to 4 loop
      pulse(100000000);
      check("output stays clamped", -servo_clamp_c);
    end loop;

    -- The integrator saturated at the clamp instead of winding up to
    -- 5 * 1562500, so the proportional term of a reversed offset
    -- takes the output positive at once.
    pulse(-640000);
    check("recovery without windup", 70000);

    clear;
    pulse(-100000000);
    check("output clamp, other rail", servo_clamp_c);

    log_info(ctxt, "servo unit test done");
    done_s(0) <= '1';
    wait;
  end process;

  su: nsl_time.discipline.discipline_pi_servo
    generic map(
      kp_l2_c => servo_kp_l2_c,
      ki_l2_c => servo_ki_l2_c,
      freq_clamp_ppb_c => servo_clamp_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      clear_i => su_clear_s,
      offset_i => su_offset_s,
      offset_valid_i => su_valid_s,
      freq_offset_ppb_o => su_ppb_s
      );

  dac_unit: process is
    constant ctxt : log_context := "dac";

    procedure apply(ppb : integer;
                    a_code, b_code : integer;
                    a_pulses, b_pulses : integer) is
      variable a_count, b_count : integer;
    begin
      a_count := 0;
      b_count := 0;
      wait until falling_edge(clock_s);
      du_ppb_s <= to_signed(ppb, du_ppb_s'length);
      for i in 1 to 8 loop
        wait until rising_edge(clock_s);
        if du_a_changed_s = '1' then
          a_count := a_count + 1;
        end if;
        if du_b_changed_s = '1' then
          b_count := b_count + 1;
        end if;
      end loop;
      assert_equal(ctxt, "direct code", to_integer(du_a_code_s), a_code, failure);
      assert_equal(ctxt, "inverted code", to_integer(du_b_code_s), b_code, failure);
      assert_equal(ctxt, "direct changed pulses", a_count, a_pulses, failure);
      assert_equal(ctxt, "inverted changed pulses", b_count, b_pulses, failure);
    end procedure;
  begin
    done_s(1) <= '0';
    du_ppb_s <= (others => '0');

    wait until reset_n_s = '1';
    wait for clock_period_c * 4;

    -- Instance a: 65536 ppb of full scale over 16 bits, one code per
    -- ppb.  Instance b: 131072 ppb of full scale, inverted, half a
    -- code per ppb.
    apply(0, 32768, 32768, 0, 0);
    apply(1000, 33768, 32268, 1, 1);
    apply(-1000, 31768, 33268, 1, 1);
    apply(40000, 65535, 12768, 1, 1);
    -- Instance a is already railed, its code does not move.
    apply(41000, 65535, 12268, 0, 1);
    apply(-40000, 0, 52768, 1, 1);
    apply(0, 32768, 32768, 1, 1);

    log_info(ctxt, "DAC driver unit test done");
    done_s(1) <= '1';
    wait;
  end process;

  du_a: nsl_time.discipline.discipline_dac_driver
    generic map(
      dac_width_c => dac_width_c,
      full_scale_ppb_c => 65536,
      invert_c => false
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      freq_offset_ppb_i => du_ppb_s,
      dac_o => du_a_code_s,
      changed_o => du_a_changed_s
      );

  du_b: nsl_time.discipline.discipline_dac_driver
    generic map(
      dac_width_c => dac_width_c,
      full_scale_ppb_c => 131072,
      invert_c => true
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      freq_offset_ppb_i => du_ppb_s,
      dac_o => du_b_code_s,
      changed_o => du_b_changed_s
      );

  clock_driver_unit: process is
    constant ctxt : log_context := "clkdrv";

    procedure apply(ppb : integer; expected : real) is
      variable got : real;
    begin
      wait until falling_edge(clock_s);
      cu_ppb_s <= to_signed(ppb, cu_ppb_s'length);
      -- A correction crosses through a handshake, whose round trip
      -- takes a handful of cycles of the slowest of the two clocks.
      for i in 1 to 24 loop
        wait until falling_edge(clock_s);
      end loop;
      got := to_real(cu_inc_s);
      assert abs(got - expected) < 3.0 * 2.0 ** cu_inc_s'right
        report "Increment for " & integer'image(ppb) & " ppb is "
        & real'image(got) & ", expected " & real'image(expected)
        severity failure;
    end procedure;
  begin
    done_s(2) <= '0';
    cu_ppb_s <= (others => '0');

    wait until reset_n_s = '1';
    wait for clock_period_c * 4;

    apply(0, cu_nominal_ns_c);
    apply(100000, cu_nominal_ns_c * (1.0 + 100000.0e-9));
    apply(-100000, cu_nominal_ns_c * (1.0 - 100000.0e-9));
    apply(1000000, cu_nominal_ns_c * (1.0 + 1000000.0e-9));

    log_info(ctxt, "clock driver unit test done");
    done_s(2) <= '1';
    wait;
  end process;

  cu: nsl_time.discipline.discipline_clock_driver
    generic map(
      clock_hz_c => cu_clock_hz_c
      )
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,
      freq_offset_ppb_i => cu_ppb_s,
      rtc_clock_i => clock_s,
      sub_nanosecond_inc_o => cu_inc_s
      );

  closed_loop: process is
    constant ctxt : log_context := "loop";
    variable offset : integer;
    variable worst : integer;
  begin
    done_s(3) <= '0';
    loop_run_s <= '0';
    force_set_s <= '0';
    ref_force_s.abs_change <= '0';
    ref_force_s.second <= (others => '-');
    ref_force_s.nanosecond <= (others => '-');
    disc_force_s.abs_change <= '0';
    disc_force_s.second <= (others => '-');
    disc_force_s.nanosecond <= (others => '-');

    wait until reset_n_s = '1';
    wait for clock_period_c * 4;

    -- Both clocks start on the same second, the disciplined one
    -- ahead by a phase step on top of its frequency error.
    wait until falling_edge(clock_s);
    ref_force_s.second <= to_unsigned(1, ref_force_s.second'length);
    ref_force_s.nanosecond <= to_unsigned(0, ref_force_s.nanosecond'length);
    disc_force_s.second <= to_unsigned(1, disc_force_s.second'length);
    disc_force_s.nanosecond <= to_unsigned(initial_offset_ns_c,
                                           disc_force_s.nanosecond'length);
    force_set_s <= '1';
    wait until rising_edge(clock_s);
    wait until falling_edge(clock_s);
    force_set_s <= '0';
    ref_force_s.second <= (others => '-');
    ref_force_s.nanosecond <= (others => '-');
    disc_force_s.second <= (others => '-');
    disc_force_s.nanosecond <= (others => '-');

    wait for clock_period_c * 10;
    wait until falling_edge(clock_s);
    loop_run_s <= '1';

    worst := 0;
    for i in 1 to settle_period_count_c loop
      wait until rising_edge(clock_s) and loop_valid_s = '1';
      offset := to_integer(loop_offset_s);
      if abs(offset) > worst then
        worst := abs(offset);
      end if;
    end loop;
    log_info(ctxt, "peak offset during acquisition: "
             & integer'image(worst) & " ns");

    worst := 0;
    for i in 1 to check_period_count_c loop
      wait until rising_edge(clock_s) and loop_valid_s = '1';
      offset := to_integer(loop_offset_s);
      if abs(offset) > worst then
        worst := abs(offset);
      end if;
      assert abs(offset) <= residual_bound_ns_c
        report "Offset " & integer'image(offset)
        & " ns is past the residual bound at measurement "
        & integer'image(i)
        severity failure;
    end loop;
    log_info(ctxt, "residual offset after convergence: " & integer'image(worst)
             & " ns, correction " & integer'image(to_integer(loop_ppb_s))
             & " ppb");

    done_s(3) <= '1';
    wait;
  end process;

  strober: process(clock_s, reset_n_s) is
    variable count : natural;
  begin
    if rising_edge(clock_s) then
      loop_valid_s <= '0';
      if count = 0 then
        count := meas_period_c - 1;
        loop_valid_s <= loop_run_s;
      else
        count := count - 1;
      end if;
    end if;

    if reset_n_s = '0' then
      count := meas_period_c - 1;
      loop_valid_s <= '0';
    end if;
  end process;

  reference: nsl_time.clock.clock_adjustable
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      sub_nanosecond_inc_i => inc_nominal_c,
      timestamp_i => ref_force_s,
      timestamp_set_i => force_set_s,
      timestamp_o => ref_time_s
      );

  disc_inc_s <= drv_inc_s + inc_error_c;

  disciplined: nsl_time.clock.clock_adjustable
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      sub_nanosecond_inc_i => disc_inc_s,
      timestamp_i => disc_force_s,
      timestamp_set_i => force_set_s,
      timestamp_o => disc_time_s
      );

  measurer: nsl_time.skew.skew_measurer
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      reference_i => ref_time_s,
      skewed_i => disc_time_s,
      offset_o => loop_offset_s
      );

  servo: nsl_time.discipline.discipline_pi_servo
    generic map(
      kp_l2_c => loop_kp_l2_c,
      ki_l2_c => loop_ki_l2_c,
      freq_clamp_ppb_c => 100000
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      offset_i => loop_offset_s,
      offset_valid_i => loop_valid_s,
      freq_offset_ppb_o => loop_ppb_s
      );

  driver_inst: nsl_time.discipline.discipline_clock_driver
    generic map(
      clock_hz_c => integer(clock_freq_c)
      )
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,
      freq_offset_ppb_i => loop_ppb_s,
      rtc_clock_i => clock_s,
      sub_nanosecond_inc_o => drv_inc_s
      );

  multi_domain_loop: process is
    constant ctxt : log_context := "mloop";
    variable offset : integer;
    variable worst : integer;
  begin
    done_s(4) <= '0';
    mloop_run_s <= '0';
    mforce_set_s <= '0';
    mref_force_s.abs_change <= '0';
    mref_force_s.second <= (others => '-');
    mref_force_s.nanosecond <= (others => '-');
    mdisc_force_s.abs_change <= '0';
    mdisc_force_s.second <= (others => '-');
    mdisc_force_s.nanosecond <= (others => '-');

    wait until reset_n_s = '1';
    wait for clock_period_c * 4;

    -- The two time bases are set from the same command, but each takes
    -- it on an edge of its own clock and resumes on the next one, so
    -- the phase error at start is the deliberate step plus up to a
    -- period of either clock.
    wait until falling_edge(clock_s);
    mref_force_s.second <= to_unsigned(1, mref_force_s.second'length);
    mref_force_s.nanosecond <= to_unsigned(0, mref_force_s.nanosecond'length);
    mdisc_force_s.second <= to_unsigned(1, mdisc_force_s.second'length);
    mdisc_force_s.nanosecond <= to_unsigned(minitial_offset_ns_c,
                                            mdisc_force_s.nanosecond'length);
    mforce_set_s <= '1';
    wait for clock_period_c * 2 + rtc_period_c;
    wait until falling_edge(clock_s);
    mforce_set_s <= '0';
    mref_force_s.second <= (others => '-');
    mref_force_s.nanosecond <= (others => '-');
    mdisc_force_s.second <= (others => '-');
    mdisc_force_s.nanosecond <= (others => '-');

    wait for clock_period_c * 10;
    wait until falling_edge(clock_s);
    mloop_run_s <= '1';

    worst := 0;
    for i in 1 to msettle_period_count_c loop
      wait until rising_edge(rtc_clock_s) and mfilt_valid_s = '1';
      offset := to_integer(mfilt_offset_s);
      if abs(offset) > worst then
        worst := abs(offset);
      end if;
    end loop;
    log_info(ctxt, "peak offset during acquisition: "
             & integer'image(worst) & " ns");

    worst := 0;
    for i in 1 to mcheck_period_count_c loop
      wait until rising_edge(rtc_clock_s) and mfilt_valid_s = '1';
      offset := to_integer(mfilt_offset_s);
      if abs(offset) > worst then
        worst := abs(offset);
      end if;
      assert abs(offset) <= mresidual_bound_ns_c
        report "Offset " & integer'image(offset)
        & " ns is past the residual bound at measurement "
        & integer'image(i)
        severity failure;
    end loop;
    log_info(ctxt, "residual offset after convergence: " & integer'image(worst)
             & " ns, correction " & integer'image(to_integer(mloop_ppb_s))
             & " ppb");

    done_s(4) <= '1';
    wait;
  end process;

  mstrober: process(rtc_clock_s, reset_n_s) is
    variable count : natural;
  begin
    if rising_edge(rtc_clock_s) then
      mstrobe_s <= '0';
      if count = 0 then
        count := mmeas_period_c - 1;
        mstrobe_s <= mloop_run_s;
      else
        count := count - 1;
      end if;
    end if;

    if reset_n_s = '0' then
      count := mmeas_period_c - 1;
      mstrobe_s <= '0';
    end if;
  end process;

  -- The reference time reaches the measurer as a plain sample taken by
  -- the time base clock, which is what a bench can do and a real
  -- system would not have to: a sample landing on the very edge where
  -- the reference steps mixes two times, and shows up as an offset of
  -- the order of a second.  Such a reading is dropped rather than fed
  -- to the servo.
  mfilter: process(rtc_clock_s, reset_n_s) is
  begin
    if rising_edge(rtc_clock_s) then
      mfilt_valid_s <= '0';
      if mmeas_strobe_s = '1'
        and mmeas_offset_s < 500000000
        and mmeas_offset_s > -500000000 then
        mfilt_valid_s <= '1';
        mfilt_offset_s <= mmeas_offset_s;
      end if;
    end if;

    if reset_n_s = '0' then
      mfilt_valid_s <= '0';
    end if;
  end process;

  mreference: nsl_time.clock.clock_adjustable
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      sub_nanosecond_inc_i => inc_nominal_c,
      timestamp_i => mref_force_s,
      timestamp_set_i => mforce_set_s,
      timestamp_o => mref_time_s
      );

  mdisc_inc_s <= mdrv_inc_s + minc_error_c;

  mdisciplined: nsl_time.clock.clock_adjustable
    port map(
      clock_i => rtc_clock_s,
      reset_n_i => reset_n_s,
      sub_nanosecond_inc_i => mdisc_inc_s,
      timestamp_i => mdisc_force_s,
      timestamp_set_i => mforce_set_s,
      timestamp_o => mdisc_time_s
      );

  mmeasurer: nsl_time.skew.skew_measurer
    port map(
      clock_i => rtc_clock_s,
      reset_n_i => reset_n_s,
      strobe_i => mstrobe_s,
      reference_i => mref_time_s,
      skewed_i => mdisc_time_s,
      strobe_o => mmeas_strobe_s,
      offset_o => mmeas_offset_s
      );

  moffset_crossing: nsl_clocking.interdomain.interdomain_fifo_slice
    generic map(
      data_width_c => timestamp_nanosecond_offset_t'length
      )
    port map(
      reset_n_i => reset_n_s,
      clock_i(0) => rtc_clock_s,
      clock_i(1) => clock_s,

      in_data_i => std_ulogic_vector(mfilt_offset_s),
      in_valid_i => mfilt_valid_s,
      in_ready_o => open,

      out_data_o => mservo_offset_slv_s,
      out_ready_i => '1',
      out_valid_o => mservo_valid_s
      );

  mservo_offset_s <= signed(mservo_offset_slv_s);

  mservo: nsl_time.discipline.discipline_pi_servo
    generic map(
      kp_l2_c => loop_kp_l2_c,
      ki_l2_c => loop_ki_l2_c,
      freq_clamp_ppb_c => 100000
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      offset_i => mservo_offset_s,
      offset_valid_i => mservo_valid_s,
      freq_offset_ppb_o => mloop_ppb_s
      );

  mdriver: nsl_time.discipline.discipline_clock_driver
    generic map(
      clock_hz_c => rtc_hz_c
      )
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,
      freq_offset_ppb_i => mloop_ppb_s,
      rtc_clock_i => rtc_clock_s,
      sub_nanosecond_inc_o => mdrv_inc_s
      );

  applier_time: process(clock_s, reset_n_s) is
    variable sec, ns : integer;
  begin
    if rising_edge(clock_s) then
      ns := ns + applier_step_ns_c;
      if ns >= 1000000000 then
        ns := ns - 1000000000;
        sec := sec + 1;
      end if;
      au_ts_s.second <= to_unsigned(sec, au_ts_s.second'length);
      au_ts_s.nanosecond <= to_unsigned(ns, au_ts_s.nanosecond'length);
    end if;

    if reset_n_s = '0' then
      sec := applier_start_sec_c;
      ns := applier_start_ns_c;
      au_ts_s.second <= to_unsigned(sec, au_ts_s.second'length);
      au_ts_s.nanosecond <= to_unsigned(ns, au_ts_s.nanosecond'length);
    end if;
  end process;

  au_ts_s.abs_change <= '0';

  applier_unit: process is
    constant ctxt : log_context := "applier";
    variable now_v : timestamp_t;
    variable sync_v, ref_v : timestamp_t;
  begin
    done_s(5) <= '0';
    au_valid_s <= '0';
    au_ref_s <= timestamp_zero_c;
    au_sync_s <= timestamp_zero_c;

    wait until reset_n_s = '1';
    wait for clock_period_c * 8;

    -- A tenth of a second of local time between the event and the
    -- command, and a reference a couple of million seconds away from
    -- the local time base.  Both the borrow of the difference and the
    -- carry of the sum are exercised.
    wait until falling_edge(clock_s);
    now_v := au_ts_s;
    sync_v := ts_add(now_v, (sec => -1, ns => 700000000));
    ref_v := ts_add(timestamp_zero_c, (sec => 2000000, ns => 100000000));
    applier_case(ctxt, "near reference", ref_v, sync_v,
                 clock_s, clock_s,
                 au_ref_s, au_sync_s, au_valid_s,
                 au_ts_s, au_out_s, au_set_s);

    -- A hundred seconds between the event and now: the second part of
    -- the difference is far outside anything a nanosecond offset can
    -- hold, and the result still has to be exact.
    wait until falling_edge(clock_s);
    now_v := au_ts_s;
    sync_v := ts_add(now_v, (sec => -100, ns => 0));
    ref_v := ts_add(timestamp_zero_c, (sec => 5, ns => 900000000));
    applier_case(ctxt, "hundred seconds of lag", ref_v, sync_v,
                 clock_s, clock_s,
                 au_ref_s, au_sync_s, au_valid_s,
                 au_ts_s, au_out_s, au_set_s);

    -- Reference behind the local time base, so the second part of the
    -- difference is negative by a hundred seconds.
    wait until falling_edge(clock_s);
    now_v := au_ts_s;
    sync_v := ts_add(now_v, (sec => 100, ns => 0));
    ref_v := ts_add(timestamp_zero_c, (sec => 900000, ns => 250000000));
    applier_case(ctxt, "reference behind", ref_v, sync_v,
                 clock_s, clock_s,
                 au_ref_s, au_sync_s, au_valid_s,
                 au_ts_s, au_out_s, au_set_s);

    log_info(ctxt, "step applier unit test done");
    done_s(5) <= '1';
    wait;
  end process;

  au: nsl_time.discipline.discipline_step_applier
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,
      reference_i => au_ref_s,
      sync_i => au_sync_s,
      valid_i => au_valid_s,
      rtc_clock_i => clock_s,
      timestamp_i => au_ts_s,
      timestamp_o => au_out_s,
      timestamp_set_o => au_set_s
      );

  applier_x_time: process(rtc_clock_s, reset_n_s) is
    variable sec, ns : integer;
  begin
    if rising_edge(rtc_clock_s) then
      ns := ns + applier_step_ns_c;
      if ns >= 1000000000 then
        ns := ns - 1000000000;
        sec := sec + 1;
      end if;
      ax_ts_s.second <= to_unsigned(sec, ax_ts_s.second'length);
      ax_ts_s.nanosecond <= to_unsigned(ns, ax_ts_s.nanosecond'length);
    end if;

    if reset_n_s = '0' then
      sec := applier_start_sec_c;
      ns := applier_start_ns_c;
      ax_ts_s.second <= to_unsigned(sec, ax_ts_s.second'length);
      ax_ts_s.nanosecond <= to_unsigned(ns, ax_ts_s.nanosecond'length);
    end if;
  end process;

  ax_ts_s.abs_change <= '0';

  applier_cross: process is
    constant ctxt : log_context := "applierx";
    variable now_v : timestamp_t;
    variable sync_v, ref_v : timestamp_t;
  begin
    done_s(6) <= '0';
    ax_valid_s <= '0';
    ax_ref_s <= timestamp_zero_c;
    ax_sync_s <= timestamp_zero_c;

    wait until reset_n_s = '1';
    wait for clock_period_c * 8;

    wait until falling_edge(clock_s);
    now_v := ax_ts_s;
    sync_v := ts_add(now_v, (sec => -1, ns => 700000000));
    ref_v := ts_add(timestamp_zero_c, (sec => 2000000, ns => 100000000));
    applier_case(ctxt, "near reference", ref_v, sync_v,
                 clock_s, rtc_clock_s,
                 ax_ref_s, ax_sync_s, ax_valid_s,
                 ax_ts_s, ax_out_s, ax_set_s);

    wait until falling_edge(clock_s);
    now_v := ax_ts_s;
    sync_v := ts_add(now_v, (sec => -100, ns => 0));
    ref_v := ts_add(timestamp_zero_c, (sec => 5, ns => 900000000));
    applier_case(ctxt, "hundred seconds of lag", ref_v, sync_v,
                 clock_s, rtc_clock_s,
                 ax_ref_s, ax_sync_s, ax_valid_s,
                 ax_ts_s, ax_out_s, ax_set_s);

    log_info(ctxt, "step applier crossing test done");
    done_s(6) <= '1';
    wait;
  end process;

  ax: nsl_time.discipline.discipline_step_applier
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,
      reference_i => ax_ref_s,
      sync_i => ax_sync_s,
      valid_i => ax_valid_s,
      rtc_clock_i => rtc_clock_s,
      timestamp_i => ax_ts_s,
      timestamp_o => ax_out_s,
      timestamp_set_o => ax_set_s
      );

  -- Coherence of the driver output.  The command is walked bit by bit
  -- over a window that holds no rising edge of the command clock, the
  -- way a bus with skew between its bits reaches another domain.
  -- Whatever the time base clock does during that window, the
  -- increment must be one of the two settled values: an implementation
  -- sampling the command with the time base clock instead of crossing
  -- it catches a mixture of the two, and a mixture is a frequency
  -- nobody asked for.
  coherence_unit: process is
    constant ctxt : log_context := "coher";
    variable v : frequency_ppb_t;
  begin
    done_s(7) <= '0';
    tu_arm_s <= '0';
    tu_ppb_s <= (others => '0');

    wait until reset_n_s = '1';
    wait for clock_period_c * 20;
    tu_low_inc_s <= tu_inc_s;

    tu_ppb_s <= to_signed(tu_ppb_c, tu_ppb_s'length);
    wait for clock_period_c * 20;
    tu_high_inc_s <= tu_inc_s;
    wait for clock_period_c;
    tu_arm_s <= '1';

    for i in 1 to tu_transition_count_c loop
      wait until rising_edge(clock_s);
      if (i mod 2) = 1 then
        v := (others => '0');
      else
        v := to_signed(tu_ppb_c, v'length);
      end if;

      for b in tu_ppb_s'left downto tu_ppb_s'right loop
        tu_ppb_s(b) <= v(b);
        wait for tu_bit_skew_c;
      end loop;

      wait for clock_period_c * 8;
    end loop;

    tu_arm_s <= '0';
    log_info(ctxt, "clock driver coherence test done");
    done_s(7) <= '1';
    wait;
  end process;

  coherence_check: process(rtc_clock_s) is
  begin
    if rising_edge(rtc_clock_s) then
      if tu_arm_s = '1' then
        assert tu_inc_s = tu_low_inc_s or tu_inc_s = tu_high_inc_s
          report "Clock driver increment is neither of the commanded values"
          severity failure;
      end if;
    end if;
  end process;

  tu: nsl_time.discipline.discipline_clock_driver
    generic map(
      clock_hz_c => rtc_hz_c
      )
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,
      freq_offset_ppb_i => tu_ppb_s,
      rtc_clock_i => rtc_clock_s,
      sub_nanosecond_inc_o => tu_inc_s
      );

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 2,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => clock_period_c,
      clock_period(1) => rtc_period_c,
      reset_duration(0) => clock_period_c * 3,
      reset_n_o(0) => reset_n_s,
      clock_o(0) => clock_s,
      clock_o(1) => rtc_clock_s,
      done_i => done_s
      );

end;
