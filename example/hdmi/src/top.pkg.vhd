library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work, nsl_color, nsl_io, nsl_clocking, unisim, nsl_i2c;
use nsl_color.rgb.all;

package top is
    
  component main is
    generic (
      clock_i_hz_c : natural
      );
    port (
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      button_i : in std_ulogic_vector(0 to 3);
      switch_i : in std_ulogic_vector(0 to 1);
      led_o: out std_ulogic_vector(0 to 3);
      led4_o, led5_o: out rgb3;

      hdmi_i2c_o : out nsl_i2c.i2c.i2c_o;
      hdmi_i2c_i : in nsl_i2c.i2c.i2c_i;
      hdmi_clock_o : out nsl_io.diff.diff_pair;
      hdmi_data_o : out nsl_io.diff.diff_pair_vector(0 to 2);
      hdmi_cec_o: out nsl_io.io.opendrain;
      hdmi_cec_i: in std_ulogic;
      hdmi_hpd_i: in std_ulogic
      );
  end component;

end package;
