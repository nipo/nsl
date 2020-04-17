library ieee;
use ieee.std_logic_1164.all;

library signalling, nsl, hwdep, util;
use signalling.color.all;

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
  signal s_color: signalling.color.rgb24;

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
      p_led(0) => s_color
      );

  en <= '1';

  prio: util.activity.activity_rgb_priority_encoder
    generic map(
      activity_count => act'length
      )
    port map(
      p_led => s_color,
      p_colors(0) => (255, 0, 0),
      p_colors(1) => (255, 63, 0),
      p_colors(2) => (255, 127, 0),
      p_colors(3) => (255, 191, 0),
      p_colors(4) => (255, 255, 0),
      p_colors(5) => (191, 255, 0),
      p_colors(6) => (127, 255, 0),
      p_colors(7) => (63, 255, 0),
      p_colors(8) => (0, 255, 0),
      p_colors(9) => (0, 255, 63),
      p_colors(10) => (0, 255, 127),
      p_colors(11) => (0, 255, 191),
      p_colors(12) => (0, 255, 255),
      p_colors(13) => (0, 191, 255),
      p_colors(14) => (0, 127, 255),
      p_colors(15) => (0, 63, 255),
      p_colors(16) => (0, 0, 255),
      p_colors(17) => (63, 0, 255),
      p_colors(18) => (127, 0, 255),
      p_colors(19) => (191, 0, 255),
      p_colors(20) => (255, 0, 255),
      p_colors(21) => (255, 0, 191),
      p_colors(22) => (255, 0, 127),
      p_colors(23) => (255, 0, 63),
      p_activity => act
      );
  
end arch;
