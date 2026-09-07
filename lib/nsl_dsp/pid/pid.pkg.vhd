library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math;
use nsl_math.fixed.all;

package pid is

  -- Pipelined PID controller on the error e = set_point - measure:
  --   control = kp*e + ki*sum(e) + kd*(e - e_previous)
  --
  -- Each valid_i pulse is one sample; the sample period is folded
  -- into the gains, there is no dt input.  The pipeline accepts a
  -- sample every cycle and pulses changed_o with the matching
  -- control_o six cycles later.
  --
  -- Anti-windup: with control_min_i/control_max_i connected (both or
  -- neither), the integrator clamps to the output window -- it
  -- accumulates post-gain, so the limits apply directly whatever the
  -- gains -- and the output clamps to the same window; residual
  -- overshoot of the pre-clamp sum is bounded to one P+D
  -- contribution.  Without limits, the integrator saturates ni_c
  -- bits above the ki product and the output saturates at the range
  -- of control_o.  The derivative acts on the error, so a set point
  -- step kicks it.
  --
  -- Leaving ki_i or kd_i unconnected removes the branch: the
  -- controller degrades to PD, PI or P.
  component pid_sfixed is
    generic(
      ni_c: positive := 8
      );
    port(
      clock_i: in std_ulogic;
      reset_n_i : in std_ulogic;

      -- One sample per pulse.
      valid_i: in std_ulogic := '1';
      -- Must be of the same range.
      set_point_i: in sfixed;
      measure_i: in sfixed;

      kp_i: in sfixed;
      ki_i: in sfixed := nasf;
      kd_i: in sfixed := nasf;

      -- Runtime output window, applied to the integrator and the
      -- output.  Connect both or neither.
      control_min_i: in sfixed := nasf;
      control_max_i: in sfixed := nasf;

      changed_o: out std_ulogic;
      control_o : out sfixed
      );
  end component;

  -- Pipelined PD-D2 controller on the error e = set_point - measure:
  --   control = kp*e + kd*(e - e_prev) + kd2*(e - 2*e_prev + e_prev2)
  --
  -- Same conventions as pid_sfixed: gains fold the sample period in,
  -- one sample per valid_i pulse, changed_o pulses with the matching
  -- control_o eight cycles later.  A null-range set_point_i means a
  -- constant zero set point.
  component pdd2_sfixed is
    port(
      clock_i: in std_ulogic;
      reset_n_i : in std_ulogic;

      -- One sample per pulse.
      valid_i: in std_ulogic;
      -- Must be of the same range, or set_point_i null for zero.
      set_point_i: in sfixed;
      measure_i: in sfixed;

      kp_i: in sfixed;
      kd_i: in sfixed;
      kd2_i: in sfixed;

      changed_o: out std_ulogic;
      control_o : out sfixed
      );
  end component;
  
end package pid;
