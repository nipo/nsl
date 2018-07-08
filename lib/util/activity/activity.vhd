library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library util, signalling;

package activity is

  component activity_monitor
    generic (
      blink_time : natural;
      on_value : std_ulogic := '1'
      );
    port (
      p_resetn      : in  std_ulogic;
      p_clk         : in  std_ulogic;
      p_togglable   : in  std_ulogic;
      p_activity    : out std_ulogic
      );
  end component;

  component activity_rgb_priority_encoder
    generic (
      activity_count : natural
      );
    port (
      p_led      : out signalling.color.rgb24;
      p_colors   : in  signalling.color.rgb24_vector(activity_count - 1 downto 0);
      p_activity : in  std_ulogic_vector(activity_count - 1 downto 0)
      );
  end component;

end package activity;
