library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math;
use nsl_math.fixed.all;
use nsl_math.real_ext.all;

package rom_fixed is

  component rom_ufixed is
    generic(
      values_c : real_vector
      );
    port(
      clock_i: in std_ulogic;
      reset_n_i : in std_ulogic;

      address_i : in unsigned(nsl_math.arith.log2(values_c'length-1)-1 downto 0);
      value_o : out ufixed
      );
  end component;    

  component rom_sfixed is
    generic(
      values_c : real_vector
      );
    port(
      clock_i: in std_ulogic;
      reset_n_i : in std_ulogic;

      address_i : in unsigned(nsl_math.arith.log2(values_c'length-1)-1 downto 0);
      value_o : out sfixed
      );
  end component;    

end package rom_fixed;
