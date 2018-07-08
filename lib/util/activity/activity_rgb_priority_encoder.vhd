library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library signalling;

entity activity_rgb_priority_encoder is
  generic (
    activity_count : natural
    );
  port (
    p_led      : out signalling.color.rgb24;
    p_colors   : in  signalling.color.rgb24_vector(activity_count - 1 downto 0);
    p_activity : in  std_ulogic_vector(activity_count - 1 downto 0)
    );
end activity_rgb_priority_encoder;

architecture rtl of activity_rgb_priority_encoder is

  signal current : natural range 0 to activity_count-1;
  
begin

  d: process(p_activity)
  begin
    current <= 0;

    for i in 0 to activity_count-1 loop
      if p_activity(i) = '1' then
        current <= i;
      end if;
    end loop;

  end process;

  p_led <= p_colors(current);
  
end rtl;
