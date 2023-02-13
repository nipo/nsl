library ieee;
use ieee.std_logic_1164.all;

library nsl_math;
use nsl_math.fixed.all;

package box is

  -- This a box filter, i.e. a moving average.
  -- It only supports power-of-two number of terms.
  component box_ufixed is
    generic(
      count_l2_c : natural
      );
    port(
      clock_i: in std_ulogic;
      reset_n_i : in std_ulogic;

      valid_i : in std_ulogic := '1';
      in_i : in ufixed;
      out_o : out ufixed
      );
  end component;

  -- This a box filter, i.e. a moving average.
  -- It only supports power-of-two number of terms.
  component box_sfixed is
    generic(
      count_l2_c : natural
      );
    port(
      clock_i: in std_ulogic;
      reset_n_i : in std_ulogic;

      valid_i : in std_ulogic := '1';
      in_i : in sfixed;
      out_o : out sfixed
      );
  end component;

end package;
