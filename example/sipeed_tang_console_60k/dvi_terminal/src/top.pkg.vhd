library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work, nsl_color, nsl_io, nsl_clocking;
use nsl_color.rgb.all;

package top is
    
  component main is
    generic (
      clock_i_hz_c : natural
      );
    port (
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      led_o: out std_ulogic_vector(0 to 1);

      dvi_clock_o : out nsl_io.diff.diff_pair;
      dvi_data_o : out nsl_io.diff.diff_pair_vector(0 to 2);

      uart_i: in std_ulogic
      );
  end component;

  component dvi_pll is
    port (
      clkin: in std_logic;
      clkout0: out std_logic;
      clkout1: out std_logic;
      lock: out std_logic;
      mdclk: in std_logic;
      reset: in std_logic
      );
  end component;

  component stage1_pll is
    port (
      clkin: in std_logic;
      clkout0: out std_logic;
      lock: out std_logic;
      mdclk: in std_logic;
      reset: in std_logic
      );
  end component;

end package;
