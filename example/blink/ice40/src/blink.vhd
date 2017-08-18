library ieee;
use ieee.std_logic_1164.all;
use work.all;

entity top is
  port (
    led: out std_ulogic;
    clk: in std_ulogic
  );
end top;

architecture arch of top is

  constant blink_time: integer := 6000000;
  signal cnt: integer := 0;
  signal led_state: std_ulogic := '0';

begin
  
  led <= led_state;

  process (clk)
  begin
    if (rising_edge(clk)) then
      if (cnt >= blink_time) then
        cnt <= 0;
        led_state <= not led_state;
      else
        cnt <= cnt + 1;
      end if;
    end if;
  end process;

end arch;
