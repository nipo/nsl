library ieee;
use ieee.std_logic_1164.all;

library nsl_color, nsl_hwdep, nsl_indication, nsl_ws;

entity top is
  port (
    clk: in std_ulogic;
    en: out std_ulogic;
    led: out std_ulogic;
    act: in std_ulogic_vector(23 downto 0)
  );
end top;

architecture arch of top is

  signal s_resetn: std_ulogic;
  signal s_color: nsl_color.rgb.rgb24;

begin

  rgen: nsl_hwdep.reset.reset_at_startup port map(s_resetn);

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
      color_i(0) => s_color
      );

  en <= '1';

  prio: nsl_indication.activity.activity_rgb_priority_encoder
    generic map(
      activity_count_c => act'length
      )
    port map(
      led_o => s_color,
      colors_i(0) => (255, 0, 0),
      colors_i(1) => (255, 63, 0),
      colors_i(2) => (255, 127, 0),
      colors_i(3) => (255, 191, 0),
      colors_i(4) => (255, 255, 0),
      colors_i(5) => (191, 255, 0),
      colors_i(6) => (127, 255, 0),
      colors_i(7) => (63, 255, 0),
      colors_i(8) => (0, 255, 0),
      colors_i(9) => (0, 255, 63),
      colors_i(10) => (0, 255, 127),
      colors_i(11) => (0, 255, 191),
      colors_i(12) => (0, 255, 255),
      colors_i(13) => (0, 191, 255),
      colors_i(14) => (0, 127, 255),
      colors_i(15) => (0, 63, 255),
      colors_i(16) => (0, 0, 255),
      colors_i(17) => (63, 0, 255),
      colors_i(18) => (127, 0, 255),
      colors_i(19) => (191, 0, 255),
      colors_i(20) => (255, 0, 255),
      colors_i(21) => (255, 0, 191),
      colors_i(22) => (255, 0, 127),
      colors_i(23) => (255, 0, 63),
      activity_i => act
      );
  
end arch;
