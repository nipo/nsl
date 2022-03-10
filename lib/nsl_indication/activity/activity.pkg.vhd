library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_color;

package activity is

  component activity_monitor
    generic (
      blink_cycles_c : natural;
      on_value_c : std_ulogic := '1'
      );
    port (
      reset_n_i      : in  std_ulogic;
      clock_i         : in  std_ulogic;
      togglable_i   : in  std_ulogic;
      activity_o    : out std_ulogic
      );
  end component;

  component activity_blinker
    generic (
      clock_hz_c : real;
      idle_blink_hz_c : real := 1.0;
      activity_blink_hz_c : real := 4.0;
      activity_blink_duration_c: real := 0.25
      );
    port (
      reset_n_i  : in  std_ulogic;
      clock_i    : in  std_ulogic;
      activity_i : in  std_ulogic;
      led_o      : out std_ulogic
      );
  end component;

  component activity_rgb_priority_encoder
    generic (
      activity_count_c : natural
      );
    port (
      led_o      : out nsl_color.rgb.rgb24;
      colors_i   : in  nsl_color.rgb.rgb24_vector(activity_count_c - 1 downto 0);
      activity_i : in  std_ulogic_vector(activity_count_c - 1 downto 0)
      );
  end component;

end package activity;
