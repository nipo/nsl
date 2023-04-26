library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package led is

  component complementary_led_driver is
    generic (
      clock_hz_c : in real;
      blink_rate_c : in real := 1.0e3;
      pow2_divisor_c : in boolean := true
      );
    port (
      reset_n_i     : in  std_ulogic;
      clock_i       : in  std_ulogic;

      led_i         : in  std_ulogic_vector(0 to 1);
      led_k_o       : out std_ulogic_vector(0 to 1)
      );
  end component;

end package led;
