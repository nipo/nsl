library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library signalling, nsl;
use signalling.led."/=";

entity ws_2812_multi_driver is
  generic(
    clk_freq_hz : natural;
    cycle_time_ns : natural := 208;
    led_count : natural
    );
  port(
    p_clk : in std_ulogic;
    p_resetn : in std_ulogic;

    p_data : out std_ulogic;

    p_led : in signalling.led.led_rgb8_vector(led_count-1 downto 0)
    );
end entity;

architecture rtl of ws_2812_multi_driver is

  type state_t is (
    ST_RESET,
    ST_WAIT,
    ST_PUT_LED
    );

  type regs_t is
  record
    state : state_t;
    leds : signalling.led.led_rgb8_vector(led_count-1 downto 0);
    idx : natural range 0 to led_count-1;
  end record;

  signal r, rin : regs_t;

  signal s_valid, s_ready, s_last : std_ulogic;
  signal s_led : signalling.led.led_rgb8;

begin

  regs: process(p_clk, p_resetn)
  begin
    if p_resetn = '0' then
      r.state <= ST_RESET;
    elsif rising_edge(p_clk) then
      r <= rin;
    end if;
  end process;

  transition: process(r, p_led, s_ready)
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.leds <= (others => (r => (others => '0'),
                                g => (others => '0'),
                                b => (others => '0')));
        rin.state <= ST_WAIT;

      when ST_WAIT =>
        if r.leds /= p_led then
          rin.leds <= p_led;
          rin.state <= ST_PUT_LED;
          rin.idx <= 0;
        end if;

      when ST_PUT_LED =>
        if s_ready = '1' then
          if r.idx = led_count - 1 then
            rin.state <= ST_WAIT;
          else
            rin.idx <= r.idx + 1;
          end if;
        end if;
    end case;
  end process;

  s_valid <= '1' when r.state = ST_PUT_LED else '0';
  s_last <= '1' when r.idx = led_count - 1 else '0';
  s_led <= r.leds(r.idx);

  master: nsl.ws.ws_2812_driver
    generic map(
      clk_freq_hz => clk_freq_hz,
      cycle_time_ns => cycle_time_ns
      )
    port map(
      p_clk => p_clk,
      p_resetn => p_resetn,

      p_data => p_data,
      
      p_led => s_led,
      p_last => s_last,
      p_valid => s_valid,
      p_ready => s_ready
      );

end;
