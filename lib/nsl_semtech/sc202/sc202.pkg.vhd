library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math;
use nsl_math.fixed.all;

package sc202 is

  -- This component buils a lookup table between input target voltage and sc202
  -- input command.
  --
  -- driver does its best not to glitch to 0V on output when
  -- transitioning between two non-zero voltages.
  component sc202_driver is
    generic(
      -- Scale applied to voltage_i before lookup to output value
      --
      -- For instance; if voltage_i_scale_c = 2.0, passing voltage_i(0 downto -5) =
      -- "010011" (~= 0.6), vsel_o will be "0010" (1.2V).
      voltage_i_scale_c: real := 1.0
      );
    port(
      reset_n_i   : in  std_ulogic;
      clock_i      : in  std_ulogic;

      -- Range is free.
      -- Unambiguous when at least ufixed(1 downto -4)
      -- For ufixed(1 downto -3), 1.85V and 1.6V set points are unreachable
      voltage_i : in ufixed;
      
      vsel_o : out std_ulogic_vector(3 downto 0)
      );
  end component;

end package sc202;
