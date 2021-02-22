library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_color;

package driver is

  component ws_2812_driver is
    generic(
      color_order : string := "GRB";
      clk_freq_hz : natural;
      error_ns : natural := 150;
      t0h_ns : natural := 350;
      t0l_ns : natural := 1360;
      t1h_ns : natural := 1360;
      t1l_ns : natural := 350;
      driver_inverted_c : boolean := false;
      attenuation_l2_c : integer range 0 to 7 := 0
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

  component ws_2812_multi_driver is
    generic(
      color_order : string := "GRB";
      clk_freq_hz : natural;
      error_ns : natural := 150;
      t0h_ns : natural := 350;
      t0l_ns : natural := 1360;
      t1h_ns : natural := 1360;
      t1l_ns : natural := 350;
      led_count : natural;
      driver_inverted_c : boolean := false;
      attenuation_l2_c : integer range 0 to 7 := 0
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      led_o : out std_ulogic;

      color_i : in nsl_color.rgb.rgb24_vector(0 to led_count-1)
      );
  end component;
  
end package driver;
