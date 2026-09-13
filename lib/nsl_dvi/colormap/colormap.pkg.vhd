library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_color, nsl_data, nsl_indication, nsl_math, nsl_video;

package colormap is

  -- Turns a colour-index pixel stream into a colour one, one entry
  -- of the palette per pixel.
  --
  -- Index width comes from the input configuration, which states one
  -- component: a stream of eight-bit indices looks up a palette of
  -- 256 entries.  The lookup is registered, and framing travels with
  -- the pixel it belongs to.
  component dvi_colormap_lookup is
    generic(
      in_config_c : nsl_video.pixel_stream.config_t;
      out_config_c : nsl_video.pixel_stream.config_t
      );
    port(
      clock_i : in  std_ulogic;
      reset_n_i : in std_ulogic;

      palette_i : nsl_color.rgb.rgb24_vector(0 to 2**in_config_c.component_bits-1);

      in_i : in nsl_video.pixel_stream.master_t;
      in_o : out nsl_video.pixel_stream.slave_t;

      out_o : out nsl_video.pixel_stream.master_t;
      out_i : in nsl_video.pixel_stream.slave_t
      );
  end component;

end package;
