library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_color;

-- DVI pattern generators
package pattern is

  -- By default, DVI (as defined by VESA for monitors) encodes color
  -- data as RGB.  If you're looking for a valid HDMI stream, you should look
  -- for nsl_hdmi.pattern.
  component color_bars is
    port(
      clock_i : in  std_ulogic;
      reset_n_i : in std_ulogic;

      sof_i : in  std_ulogic;
      sol_i : in  std_ulogic;
      pixel_ready_i : in std_ulogic;
      pixel_valid_o : out std_ulogic;
      pixel_o : out nsl_color.rgb.rgb24
      );
  end component;

end package;
