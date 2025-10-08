library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_color, nsl_data, nsl_indication, nsl_math;

package colormap is

  component dvi_colormap_lookup is
    generic(
      color_count_l2_c: natural
      );
    port(
      clock_i : in  std_ulogic;
      reset_n_i : in std_ulogic;

      palette_i : nsl_color.rgb.rgb24_vector(0 to 2**color_count_l2_c-1);

      sof_i : in  std_ulogic;
      sol_i : in  std_ulogic;
      pixel_ready_i : in std_ulogic;
      pixel_valid_o : out std_ulogic;
      pixel_o : out nsl_color.rgb.rgb24;

      color_ready_o : out std_ulogic;
      color_valid_i : in std_ulogic := '1';
      color_i : in unsigned(color_count_l2_c-1 downto 0)
      );
  end component;

end package;
