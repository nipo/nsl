library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_color, nsl_video;

-- Test patterns.
--
-- A pattern says nothing about what carries it: the same bars go out
-- over DVI, over HDMI, to a panel or to a file.  What differs between
-- these two is the colourspace they state a pixel in, which is a
-- property of the stream rather than of the link -- a link simply
-- sends what it is given, and what a sink asked for is settled long
-- before, in its EDID.
package pattern is

  -- Eight bars of full-scale RGB.
  --
  -- Bars restart on every line, so the first one is a whole bar wide
  -- whatever the line width is.
  component rgb_color_bars is
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

  -- The same bars, stated in YCbCr.  The stream carries luma first, as
  -- the colourspace names it, which is the order
  -- nsl_dvi.encoder.channel_map_ycbcr_c expects.
  component ycbcr_color_bars is
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
