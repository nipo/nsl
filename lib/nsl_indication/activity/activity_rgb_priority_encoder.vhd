library ieee;
use ieee.std_logic_1164.all;

library nsl_color, nsl_sensor;
use nsl_sensor.priority.active_lowest_index;

entity activity_rgb_priority_encoder is
  generic (
    activity_count_c : natural
    );
  port (
    led_o      : out nsl_color.rgb.rgb24;
    colors_i   : in  nsl_color.rgb.rgb24_vector(activity_count_c - 1 downto 0);
    activity_i : in  std_ulogic_vector(activity_count_c - 1 downto 0)
    );
end activity_rgb_priority_encoder;

architecture rtl of activity_rgb_priority_encoder is
begin

  led_o <= colors_i(active_lowest_index(activity_i, 0));
  
end rtl;
