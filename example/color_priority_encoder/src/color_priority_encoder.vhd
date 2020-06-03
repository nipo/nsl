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

  rgen: nsl_hwdep.reset.reset_at_startup
    port map(
      clock_i => clk,
      reset_n_o => s_resetn
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
      led_o => led,
      color_i(0) => s_color,
      color_i(1) => s_color
      );

  en <= '1';

  prio: nsl_indication.activity.activity_rgb_priority_encoder
    generic map(
      activity_count_c => act'length
      )
    port map(
      led_o => s_color,
      colors_i(0) => (x"FF",x"00",x"00"),
      colors_i(1) => (x"FF",x"3F",x"00"),
      colors_i(2) => (x"FF",x"7F",x"00"),
      colors_i(3) => (x"FF",x"BF",x"00"),
      colors_i(4) => (x"FF",x"FF",x"00"),
      colors_i(5) => (x"BF",x"FF",x"00"),
      colors_i(6) => (x"7F",x"FF",x"00"),
      colors_i(7) => (x"3F",x"FF",x"00"),
      colors_i(8) => (x"00",x"FF",x"00"),
      colors_i(9) => (x"00",x"FF",x"3F"),
      colors_i(10) => (x"00",x"FF",x"7F"),
      colors_i(11) => (x"00",x"FF",x"BF"),
      colors_i(12) => (x"00",x"FF",x"FF"),
      colors_i(13) => (x"00",x"BF",x"FF"),
      colors_i(14) => (x"00",x"7F",x"FF"),
      colors_i(15) => (x"00",x"3F",x"FF"),
      colors_i(16) => (x"00",x"00",x"FF"),
      colors_i(17) => (x"3F",x"00",x"FF"),
      colors_i(18) => (x"7F",x"00",x"FF"),
      colors_i(19) => (x"BF",x"00",x"FF"),
      colors_i(20) => (x"FF",x"00",x"FF"),
      colors_i(21) => (x"FF",x"00",x"BF"),
      colors_i(22) => (x"FF",x"00",x"7F"),
      colors_i(23) => (x"FF",x"00",x"3F"),
      activity_i => act
      );
  
end arch;
