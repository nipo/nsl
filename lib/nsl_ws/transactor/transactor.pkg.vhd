library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_color, nsl_bnoc;

package transactor is

  component ws_2812_driver is
    generic(
      color_order : string := "GRB";
      clk_freq_hz : natural;
      cycle_time_ns : natural := 208
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      led_o : out std_ulogic;

      color_i : in nsl_color.rgb.rgb24;
      valid_i : in  std_ulogic;
      ready_o : out std_ulogic;
      last_i : in std_ulogic
      );
  end component;

  component ws_2812_framed is
    generic(
      color_order : string := "GRB";
      clk_freq_hz : natural;
      cycle_time_ns : natural := 208
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      led_o : out std_ulogic;

      cmd_i   : in nsl_bnoc.framed.framed_req;
      cmd_o   : out nsl_bnoc.framed.framed_ack;

      rsp_o   : out nsl_bnoc.framed.framed_req;
      rsp_i   : in nsl_bnoc.framed.framed_ack
      );
  end component;

  component ws_2812_multi_driver is
    generic(
      color_order : string := "GRB";
      clk_freq_hz : natural;
      cycle_time_ns : natural := 208;
      led_count : natural
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      led_o : out std_ulogic;

      color_i : in nsl_color.rgb.rgb24_vector(0 to led_count-1)
      );
  end component;
  
end package transactor;
