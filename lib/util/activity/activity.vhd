library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

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

end package activity;
