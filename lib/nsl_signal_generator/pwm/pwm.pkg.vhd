library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package pwm is

  -- Generates a periodic PWM signal:
  -- - active_duration_i ticks with pwm_o = active_value_i,
  -- - inactive_duration_i ticks with pwm_o = not active_value_i.
  --
  -- One tick lasts prescaler_i + 1 clock cycles.
  --
  -- If sync_i is asserted, next clock cycle will be first cycle of a
  -- new period.
  --
  -- active_duration_i, inactive_duration_i, prescaler_i and active_value_i are
  -- internally updated once per period.
  component pwm_generator
    port (
      reset_n_i      : in  std_ulogic;
      clock_i         : in  std_ulogic;

      -- Synchonize to start of a cycle
      -- Does not wait for end of prescaler countdown
      -- Acts as a soft reset.
      sync_i : in std_ulogic := '0';

      -- Asserted on last clock cycle of inactive time
      sync_o : out std_ulogic;

      -- Output, has active_value_i value for active_duration_i, not active_value_i for inactive_duration_i.
      pwm_o : out std_ulogic;

      -- Prescaler minus 1. (divides clock by prescaler_i+1)
      prescaler_i : in unsigned;
      -- Active duration in prescaler cycles
      active_duration_i : in unsigned;
      -- Inactive duration in prescaler cycles
      inactive_duration_i : in unsigned;
      active_value_i : std_ulogic := '1'
      );
  end component;

  component ss_pwm is
    port (
      reset_n_i   : in  std_ulogic;
      clock_i     : in  std_ulogic;

      pwm_o    : out std_ulogic;

      duty_i : in unsigned(7 downto 0)
      );
  end component;

end package pwm;
