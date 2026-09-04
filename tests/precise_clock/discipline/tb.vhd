library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_time, nsl_simulation, nsl_math, work;
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

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 3);

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
      for i in 1 to 4 loop
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
      clock_i_hz_c => cu_clock_hz_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      freq_offset_ppb_i => cu_ppb_s,
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
      clock_i_hz_c => integer(clock_freq_c)
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      freq_offset_ppb_i => loop_ppb_s,
      sub_nanosecond_inc_o => drv_inc_s
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
