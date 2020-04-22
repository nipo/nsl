library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_color;

entity activity_rgb_priority_encoder is
  generic (
    activity_count_c : natural
    );
  port (
    led_o      : out nsl_color.color.rgb24;
    colors_i   : in  nsl_color.color.rgb24_vector(activity_count_c - 1 downto 0);
    activity_i : in  std_ulogic_vector(activity_count_c - 1 downto 0)
    );
end activity_rgb_priority_encoder;

architecture rtl of activity_rgb_priority_encoder is

  signal current : natural range 0 to activity_count_c-1;
  
begin

  d: process(activity_i)
  begin
    current <= 0;

    for i in 0 to activity_count_c-1 loop
      if activity_i(i) = '1' then
        current <= i;
      end if;
    end loop;

  end process;

  led_o <= colors_i(current);
  
end rtl;
