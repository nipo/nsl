library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work, nsl_color, nsl_io, nsl_clocking, nsl_video;
use nsl_color.rgb.all;

package top is
    
  component main is
    generic (
      clock_i_hz_c : natural;
      mode_c : nsl_video.mode.mode_t
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



end package;
