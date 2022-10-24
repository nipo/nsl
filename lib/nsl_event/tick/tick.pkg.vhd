library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math;
use nsl_math.fixed.all;

-- Tick-based clocking
package tick is

  -- Fractional tick generator. Asserts tick_o for exactly one cycle every
  -- period_i cycles on average (period is a fixed point value here).
  component tick_generator is
    port(
      clock_i    : in  std_ulogic;
      reset_n_i  : in  std_ulogic;

      period_i : in ufixed;
      
      tick_o   : out std_ulogic
      );
  end component;

  component tick_generator_integer is
    port(
      clock_i    : in  std_ulogic;
      reset_n_i  : in  std_ulogic;

      period_m1_i : in unsigned;
      
      tick_o   : out std_ulogic
      );
  end component;

  -- Recovers an UI tick from a self-clocking signal and asserts a
  -- tick phase shifted at 180 deg once block is confident enough
  -- about the stability of the measurement.
  --
  -- 180 deg is mostly useful for actually sampling the signal at the
  -- right place.
  component tick_extractor_self_clocking is
    generic(
      period_max_c : natural range 4 to integer'high;
      run_length_max_c : natural := 3;
      tick_learn_c: natural := 64
      );
    port(
      clock_i : in  std_ulogic;
      reset_n_i : in std_ulogic;

      -- Synchronous positive-logic soft-reset
      reset_i : in std_ulogic := '0';

      -- Whether to enable learning of period
      enable_i: in std_ulogic := '1';
      -- Actual self-clocking signal.
      signal_i : in std_ulogic;

      valid_o : out std_ulogic;
      tick_180_o : out std_ulogic
      );
  end component;

  -- Extracts a tick from a strictly-periodic signal (usually, an
  -- oversampled clock). Only extracts one edge type.
  component tick_extractor_clock is
    generic(
      edge_c: std_ulogic := '1'; -- value after extracted edge, edge_c = '1' => rising
      divisor_c: positive := 1
      );
    port(
      clock_i : in  std_ulogic;
      reset_n_i : in std_ulogic;

      signal_i : in std_ulogic;
      tick_o : out std_ulogic
      );
  end component;

  -- Digital PLL where a tick of a given frequency is generated
  -- knowing fixed frequency of an input tick and frequency of running
  -- system.  Input reference tick may have skips.  This is mostly
  -- suitable for recovering clock from self-clocking signals like
  -- manchester.
  component tick_pll is
    generic(
      clock_i_hz_c : natural;
      tick_skip_max_c : natural := 2;
      tick_i_hz_c : natural;
      tick_o_hz_c : natural;
      target_ppm_c : natural
      );
    port (
      clock_i : in  std_ulogic;
      reset_n_i : in std_ulogic;
      tick_valid_i : in std_ulogic := '1';
      tick_i : in std_ulogic;
      tick_o : out std_ulogic;

      tick_i_period_o : out ufixed
      );
  end component;

  -- This divides a tick by an integer value. Period is multiplied by
  -- divisor_c. This does not introduce a phase shift, i.e. tick_o = 1
  -- implies tick_i = 1. Division by 1 is a noop.
  component tick_divisor is
    generic(
      divisor_c: positive
      );
    port(
      clock_i : in  std_ulogic;
      reset_n_i : in std_ulogic;

      tick_i : in std_ulogic;
      tick_o : out std_ulogic
      );
  end component;

  -- Measures a tick period and runs it through a lowpass filter.
  component tick_measurer is
    generic (
      -- See nsl_dsp.rc
      tau_c : natural
      );
    port (
      clock_i : in  std_ulogic;
      reset_n_i : in std_ulogic;
      tick_i : in std_ulogic;
      -- Expressed in clock_i cycles
      period_o : out ufixed
      );
  end component;

  -- Tick rate scaler in terms of powers of two.
  -- There is no phase alignment between input and output ticks.
  component tick_scaler_l2 is
    generic(
      input_period_max_c: real;
      input_resolution_c: real;
      -- output_period = input_period * 2 ** -period_scale_l2_c
      -- 1 doubles the tick rate
      period_scale_l2_c: natural;
      -- Lowpass convergence rate
      tau_c : natural
      );
    port(
      clock_i : in  std_ulogic;
      reset_n_i : in std_ulogic;

      tick_i : in std_ulogic;
      tick_o : out std_ulogic
      );
  end component;
  
  component tick_oscillator is
    port(
      clock_i : in  std_ulogic;
      reset_n_i : in std_ulogic;

      -- Half period tick
      tick_i : in std_ulogic;
      osc_o : out std_ulogic
      );
  end component;


  -- Pulse generator. Will assert output for assert_sec_c seconds every time
  -- tick_i is high. When tick_i period is less than assert_sec_c, pulse_o
  -- stays asserted.
  component tick_pulse is
    generic(
      clock_hz_c : integer;
      assert_sec_c : real
      );
    port(
      clock_i : in  std_ulogic;
      reset_n_i : in std_ulogic;

      tick_i : in std_ulogic;
      pulse_o : out std_ulogic
      );
  end component;

end package tick;
