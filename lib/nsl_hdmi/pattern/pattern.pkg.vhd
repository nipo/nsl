library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_color, nsl_video;

-- HDMI encodes colors in YCbCr by default. This component generates
-- color bars in this format.
package pattern is

  -- Same bars nsl_dvi.pattern shows, stated in YCbCr.  The stream
  -- carries luma first, as the colourspace names it, which is the
  -- order nsl_dvi.encoder.channel_map_ycbcr_c expects.
  component color_bars is
    generic(
      geometry_c : nsl_video.mode.geometry_t;
      config_c : nsl_video.pixel_stream.config_t;
      bar_width_c : natural := 128
      );
    port(
      clock_i : in  std_ulogic;
      reset_n_i : in std_ulogic;

      enable_i : in std_ulogic := '1';

      out_o : out nsl_video.pixel_stream.master_t;
      out_i : in nsl_video.pixel_stream.slave_t
      );
  end component;

end package;
