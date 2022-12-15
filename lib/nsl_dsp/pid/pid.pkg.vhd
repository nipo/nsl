library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math;
use nsl_math.fixed.all;

package pid is

  -- This is a PID controller.
  component pid_sfixed is
    generic(
      ni_c: positive := 8
      );
    port(
      clock_i: in std_ulogic;
      reset_n_i : in std_ulogic;

      -- When 1, a delta-t happens. This is ignored if busy_o is asserted.
      valid_i: in std_ulogic := '1';
      -- Should be of the same range.
      set_point_i: in sfixed;
      measure_i: in sfixed;

      kp_i: in sfixed;
      ki_i: in sfixed := nasf;
      kd_i: in sfixed := nasf;

      changed_o: out std_ulogic;
      control_o : out sfixed
      );
  end component;    

  component pdd2_sfixed is
    port(
      clock_i: in std_ulogic;
      reset_n_i : in std_ulogic;

      -- When 1, a delta-t happens. This is ignored if busy_o is asserted.
      valid_i: in std_ulogic;
      -- Should be of the same range.
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
