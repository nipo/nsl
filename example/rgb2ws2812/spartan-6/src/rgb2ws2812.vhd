library ieee;
use ieee.std_logic_1164.all;
use work.all;

library nsl_ws, nsl_color, hwdep;

entity top is
  port (
    clk: in std_ulogic;
    en: out std_ulogic;
    led: out std_ulogic;
    rgb: in nsl_color.rgb.rgb24
  );
end top;

architecture arch of top is

  signal s_resetn: std_ulogic;

begin

  rgen: hwdep.reset.reset_at_startup port map(s_resetn);

  driver: nsl_ws.transactor.ws_2812_multi_driver
    generic map(
      clk_freq_hz => 12000000,
      cycle_time_ns => 166,
      led_count => 1
      )
    port map(
      clock_i => clk,
      reset_n_i => s_resetn,
      led_o => led,
      color_i(0) => rgb
      );

  en <= '1';
  
end arch;
