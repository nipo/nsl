library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math;

package receiver is

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

  component tick_measurer is
    generic (
      tau_c : natural
      );
    port (
      clock_i : in  std_ulogic;
      reset_n_i : in std_ulogic;
      tick_i : in std_ulogic;
      period_o : out nsl_math.fixed.ufixed
      );
  end component;

end package receiver;
