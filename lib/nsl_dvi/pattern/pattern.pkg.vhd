library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_color, nsl_video;

-- DVI pattern generators
package pattern is

  -- By default, DVI (as defined by VESA for monitors) encodes color
  -- data as RGB.  If you're looking for a valid HDMI stream, you should look
  -- for nsl_hdmi.pattern.
  --
  -- Bars restart on every line, so the first one is a whole bar wide
  -- whatever the line width is.
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
