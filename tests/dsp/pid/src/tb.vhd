library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math, nsl_dsp, nsl_simulation;
use nsl_math.fixed.all;
use nsl_dsp.pid.all;
use nsl_simulation.logging.all;

entity tb is
end entity;

architecture beh of tb is

  -- All values and gains are exactly representable, so the golden
  -- model compares for equality.
  constant kp_c : real := 0.5;
  constant ki_c : real := 0.25;
  constant kd_c : real := 1.0;
  constant kd2_c : real := 0.25;

  subtype meas_t is sfixed(4 downto -2);
  subtype gain_t is sfixed(1 downto -4);
  subtype ctrl_t is sfixed(9 downto -6);

  signal clock_s : std_ulogic := '0';
  signal reset_n_s : std_ulogic := '0';
  signal done_s : boolean := false;

  signal valid_s : std_ulogic := '0';
  signal set_point_s, measure_s : meas_t := (others => '0');

  signal pid_control_s, p_control_s, lim_control_s, pdd2_control_s : ctrl_t;
  signal pid_changed_s, p_changed_s, lim_changed_s, pdd2_changed_s : std_ulogic;

  constant ctl_lo_c : real := -1.5;
  constant ctl_hi_c : real := 2.5;

  signal null_sp_s : sfixed(0 downto 1);

begin

  clock_s <= not clock_s after 5 ns when not done_s else '0';
  reset_n_s <= '1' after 40 ns;

  full: nsl_dsp.pid.pid_sfixed
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      valid_i => valid_s,
      set_point_i => set_point_s,
      measure_i => measure_s,

      kp_i => to_sfixed(kp_c, gain_t'left, gain_t'right),
      ki_i => to_sfixed(ki_c, gain_t'left, gain_t'right),
      kd_i => to_sfixed(kd_c, gain_t'left, gain_t'right),

      changed_o => pid_changed_s,
      control_o => pid_control_s
      );

  -- ki and kd left unconnected: degrades to a P controller.
  p_only: nsl_dsp.pid.pid_sfixed
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      valid_i => valid_s,
      set_point_i => set_point_s,
      measure_i => measure_s,

      kp_i => to_sfixed(kp_c, gain_t'left, gain_t'right),

      changed_o => p_changed_s,
      control_o => p_control_s
      );

  -- Runtime output window: integrator and output clamp to it.
  limited: nsl_dsp.pid.pid_sfixed
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      valid_i => valid_s,
      set_point_i => set_point_s,
      measure_i => measure_s,

      kp_i => to_sfixed(kp_c, gain_t'left, gain_t'right),
      ki_i => to_sfixed(ki_c, gain_t'left, gain_t'right),
      kd_i => to_sfixed(kd_c, gain_t'left, gain_t'right),

      control_min_i => to_sfixed(ctl_lo_c, 2, -2),
      control_max_i => to_sfixed(ctl_hi_c, 2, -2),

      changed_o => lim_changed_s,
      control_o => lim_control_s
      );

  -- Null set point: regulates the measurement to zero.
  pdd2: nsl_dsp.pid.pdd2_sfixed
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      valid_i => valid_s,
      set_point_i => null_sp_s,
      measure_i => measure_s,

      kp_i => to_sfixed(kp_c, gain_t'left, gain_t'right),
      kd_i => to_sfixed(kd_c, gain_t'left, gain_t'right),
      kd2_i => to_sfixed(kd2_c, gain_t'left, gain_t'right),

      changed_o => pdd2_changed_s,
      control_o => pdd2_control_s
      );

  stim: process is
    variable e, e_p : real;
    variable i_acc, i_lim : real := 0.0;
    variable pe, pe_p, pe_p2 : real;

    function windowed(v : real) return real is
    begin
      if v < ctl_lo_c then
        return ctl_lo_c;
      elsif v > ctl_hi_c then
        return ctl_hi_c;
      end if;
      return v;
    end function;

    procedure sample(sp, m : real) is
    begin
      wait until falling_edge(clock_s);
      set_point_s <= to_sfixed(sp, meas_t'left, meas_t'right);
      measure_s <= to_sfixed(m, meas_t'left, meas_t'right);
      valid_s <= '1';
      wait until falling_edge(clock_s);
      valid_s <= '0';
      -- The two controllers have different pipeline depths.
      wait until rising_edge(clock_s) and pid_changed_s = '1';
      wait until rising_edge(clock_s) and pdd2_changed_s = '1';
    end procedure;

    procedure check(name : string; got, expected : real) is
    begin
      assert got = expected
        report name & ": got " & real'image(got)
        & ", expected " & real'image(expected)
        severity failure;
    end procedure;

    variable sp, m : real;
  begin
    e_p := 0.0;
    pe_p := 0.0;
    pe_p2 := 0.0;

    wait until reset_n_s = '1';

    for n in 0 to 33
    loop
      -- Constant error, tracking, overshoot, then a hard windup
      -- excursion and its recovery.
      if n < 6 then
        sp := 2.0;
        m := 0.0;
      elsif n < 12 then
        sp := 2.0;
        m := 2.0;
      elsif n < 20 then
        sp := 2.0;
        m := 3.5;
      elsif n < 28 then
        sp := 2.0;
        m := -2.0;
      else
        sp := 2.0;
        m := 6.0;
      end if;

      sample(sp, m);

      -- Golden PID on the error.
      e := sp - m;
      i_acc := i_acc + ki_c * e;
      check("pid step " & integer'image(n),
            to_real(pid_control_s),
            kp_c * e + i_acc + kd_c * (e - e_p));

      check("p-only step " & integer'image(n),
            to_real(p_control_s),
            kp_c * e);

      -- Golden limited PID: integrator and output clamp to the
      -- window.
      i_lim := windowed(i_lim + ki_c * e);
      check("limited step " & integer'image(n),
            to_real(lim_control_s),
            windowed(kp_c * e + i_lim + kd_c * (e - e_p)));

      -- Golden PD-D2 regulating the measurement to zero.
      pe := -m;
      check("pdd2 step " & integer'image(n),
            to_real(pdd2_control_s),
            kp_c * pe + kd_c * (pe - pe_p)
            + kd2_c * (pe - 2.0 * pe_p + pe_p2));

      e_p := e;
      pe_p2 := pe_p;
      pe_p := pe;
    end loop;

    log_info("PID golden model checks pass");
    done_s <= true;
    nsl_simulation.control.terminate(0);
    wait;
  end process;

end architecture;
