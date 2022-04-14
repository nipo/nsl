library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_color;

-- HDMI encodes colors in YCbCr by default. This component generates
-- color bars in this format.
package pattern is

  component color_bars is
    port(
      clock_i : in  std_ulogic;
      reset_n_i : in std_ulogic;

      sof_i : in  std_ulogic;
      sol_i : in  std_ulogic;
      pixel_ready_i : in std_ulogic;
      pixel_o : out nsl_color.ycbcr.ycbcr24
      );
  end component;

end package;
