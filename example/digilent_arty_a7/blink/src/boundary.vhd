library ieee;
use ieee.std_logic_1164.all;

library nsl_hwdep;

entity boundary is
  port (
    ld_o: out std_ulogic_vector(4 to 7)
  );
end boundary;

architecture arch of boundary is

  constant blink_time: integer := 25000000;
  signal cnt: integer := 0;
  signal led_state: std_ulogic := '0';
  signal clk: std_ulogic;

begin

  clk_gen: nsl_hwdep.clock.clock_internal
    port map(
      clock_o => clk
      );
  
  ld_o(4) <= led_state;
  ld_o(5 to 7) <= "000";

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
