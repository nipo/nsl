library ieee;
use ieee.std_logic_1164.all;
use work.all;

library nsl_ws, nsl_color, nsl_hwdep, nsl_indication, nsl_clocking;

entity top is
  port (
    clk: in std_ulogic;
    en: out std_ulogic;
    user_led: out std_ulogic;
    user_btn: in std_ulogic;
    led: out std_ulogic;
    rgb: in nsl_color.rgb.rgb24
  );
end top;

architecture arch of top is

  signal async_resetn, roc_resetn, s_resetn: std_ulogic;
  signal s_led: std_ulogic;

begin

  rgen: nsl_hwdep.reset.reset_at_startup
    port map(
      clock_i => clk,
      reset_n_o => roc_resetn
      );

  async_resetn <= roc_resetn and user_btn;

  rsync: nsl_clocking.async.async_edge
    port map(
      clock_i => clk,
      data_i => async_resetn,
      data_o => s_resetn
      );
  
  driver: nsl_ws.driver.ws_2812_multi_driver
    generic map(
      clk_freq_hz => 12000000,
      color_order => "RGB",
      led_count => 2
      )
    port map(
      clock_i => clk,
      reset_n_i => s_resetn,
      led_o => s_led,
      color_i(0) => rgb,
      color_i(1) => rgb
      );

  en <= '1';
  led <= s_led;

  monitor: nsl_indication.activity.activity_monitor
    generic map(
      blink_cycles_c => 12000000 / 8
      )
    port map(
      reset_n_i => s_resetn,
      clock_i => clk,
      togglable_i => s_led,
      activity_o => user_led
      );
  
  
end arch;
