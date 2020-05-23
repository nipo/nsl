library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_color, nsl_ws;
use nsl_color.rgb."/=";

entity ws_2812_multi_driver is
  generic(
    color_order : string := "GRB";
    clk_freq_hz : natural;
    error_ns : natural := 150;
    t0h_ns : natural := 350;
    t0l_ns : natural := 1360;
    t1h_ns : natural := 1360;
    t1l_ns : natural := 350;
    led_count : natural
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    led_o : out std_ulogic;

    color_i : in nsl_color.rgb.rgb24_vector(0 to led_count-1)
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
    leds : nsl_color.rgb.rgb24_vector(0 to led_count-1);
    idx : natural range 0 to led_count-1;
  end record;

  signal r, rin : regs_t;

  signal s_valid, s_ready, s_last : std_ulogic;
  signal s_color : nsl_color.rgb.rgb24;

begin

  regs: process(clock_i, reset_n_i)
  begin
    if reset_n_i = '0' then
      r.state <= ST_RESET;
    elsif rising_edge(clock_i) then
      r <= rin;
    end if;
  end process;

  transition: process(r, color_i, s_ready)
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.leds <= (others => (r => 0,
                                g => 0,
                                b => 0));
        rin.state <= ST_WAIT;

      when ST_WAIT =>
        if r.leds /= color_i then
          rin.leds <= color_i;
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
  s_color <= r.leds(r.idx);

  master: nsl_ws.driver.ws_2812_driver
    generic map(
      color_order => color_order,
      clk_freq_hz => clk_freq_hz,
      error_ns => error_ns,
      t0h_ns => t0h_ns,
      t0l_ns => t0l_ns,
      t1h_ns => t1h_ns,
      t1l_ns => t1l_ns
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      led_o => led_o,
      
      color_i => s_color,
      last_i => s_last,
      valid_i => s_valid,
      ready_o => s_ready
      );

end;
