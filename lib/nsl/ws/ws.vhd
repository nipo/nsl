library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl, signalling;

package ws is

  component ws_2812_driver is
    generic(
      clk_freq_hz : natural;
      cycle_time_ns : natural := 208
      );
    port(
      p_clk : in std_ulogic;
      p_resetn : in std_ulogic;

      p_data : out std_ulogic;

      p_led : in signalling.color.rgb24;
      p_valid : in  std_ulogic;
      p_ready : out std_ulogic;
      p_last : in std_ulogic
      );
  end component;

  component ws_2812_framed is
    generic(
      clk_freq_hz : natural;
      cycle_time_ns : natural := 208
      );
    port(
      p_clk : in std_ulogic;
      p_resetn : in std_ulogic;

      p_data : out std_ulogic;

      p_cmd_val   : in nsl.framed.framed_req;
      p_cmd_ack   : out nsl.framed.framed_ack;

      p_rsp_val   : out nsl.framed.framed_req;
      p_rsp_ack   : in nsl.framed.framed_ack
      );
  end component;

  component ws_2812_multi_driver is
    generic(
      clk_freq_hz : natural;
      cycle_time_ns : natural := 208;
      led_count : natural
      );
    port(
      p_clk : in std_ulogic;
      p_resetn : in std_ulogic;

      p_data : out std_ulogic;

      p_led : in signalling.color.rgb24_vector(led_count-1 downto 0)
      );
  end component;
  
end package ws;
