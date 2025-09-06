library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work, nsl_color, nsl_io, nsl_clocking, nsl_digilent;
use nsl_color.rgb.all;
use nsl_digilent.pmod.all;

package top is
    
  component main is
    generic (
      clock_i_hz_c : natural
      );
    port (
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      button_i : in std_ulogic_vector(0 to 3);
      led_o: out std_ulogic_vector(0 to 1);

      pmod_dvi_io : inout pmod_double_t
      );
  end component;

  component hdmi_pll is
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
