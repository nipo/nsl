library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_color;

package rgb_led is

  -- Drives an RGB LED with 3 PWM drivers.
  component rgb24_pwm_driver
    generic (
      clock_prescaler_c : positive := 1;
      active_value_c : std_ulogic := '1'
      );
    port (
      reset_n_i     : in  std_ulogic;
      clock_i       : in  std_ulogic;

      color_i       : in nsl_color.rgb.rgb24;
      led_o         : out nsl_color.rgb.rgb3
      );
  end component;

end package rgb_led;
