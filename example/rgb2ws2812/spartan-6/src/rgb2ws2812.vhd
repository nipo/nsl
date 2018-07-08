library ieee;
use ieee.std_logic_1164.all;
use work.all;

library signalling, nsl, hwdep;

entity top is
  port (
    clk: in std_ulogic;
    en: out std_ulogic;
    led: out std_ulogic;
    rgb: in signalling.color.rgb24
  );
end top;

architecture arch of top is

  signal s_resetn: std_ulogic;

begin

  rgen: hwdep.reset.reset_at_startup port map(s_resetn);

  driver: nsl.ws.ws_2812_multi_driver
    generic map(
      clk_freq_hz => 12000000,
      cycle_time_ns => 166,
      led_count => 1
      )
    port map(
      p_clk => clk,
      p_resetn => s_resetn,
      p_data => led,
      p_led(0) => rgb
      );

  en <= '1';
  
end arch;
