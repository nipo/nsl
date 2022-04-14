library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math;

-- Clock receiver helpers.
--
-- This is not about receiving clock from an input with a clock buffer. Those
-- services are in nsl_clocking.distribution or in nsl_io.pad (for dedicated
-- clock input cells).
--
-- This is about receiving an oversampled clock, expressed as edge
-- detection (signal called tick, asserted during one working cycle
-- when received clock changes).
package receiver is

  -- Recovers a periodical tick and asserts a tick phase shifted at
  -- 180 deg once block is confident enough about the stability of the
  -- measurement.
  component receiver_tick_recovery is
    generic(
      period_max_c : natural range 4 to integer'high;
      run_length_max_c : natural := 3
      );
    port(
      clock_i : in  std_ulogic;
      reset_n_i : in std_ulogic;

      reset_i : in std_ulogic := '0';
      tick_i : in std_ulogic;

      valid_o : out std_ulogic;
      tick_180_o : out std_ulogic
      );
  end component;

  -- Digital PLL where a tick of a given frequency is generated
  -- knowing fixed frequency of an input tick and frequency of running
  -- system.  Input reference tick may have skips.  This is mostly
  -- suitable for recovering clock from self-clocking signals like
  -- manchester.
  component tick_recoverer is
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

      tick_i_period_o : out nsl_math.fixed.ufixed
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
      period_o : out nsl_math.fixed.ufixed
      );
  end component;

end package receiver;
