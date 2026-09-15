library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_video;

-- Pixel stream blenders
package blender is

  -- Blends two colour-index pixel streams into one.  An overlay pixel
  -- matching key_color_c is replaced by the underlay pixel, any other
  -- overlay pixel is passed through.  One beat is consumed from both
  -- inputs for every output beat, keeping the streams in lockstep,
  -- and framing is taken from the overlay.
  --
  -- The datapath is combinational.  Typical usage is between two
  -- colour-index generators and a shared
  -- nsl_video.colormap.colormap_lookup instance, with key_color_c
  -- reserved as the transparent entry of the overlay.
  component blender_color_key is
    generic(
      config_c: nsl_video.pixel_stream.config_t;
      key_color_c: natural := 0
      );
    port(
      overlay_i : in nsl_video.pixel_stream.master_t;
      overlay_o : out nsl_video.pixel_stream.slave_t;

      underlay_i : in nsl_video.pixel_stream.master_t;
      underlay_o : out nsl_video.pixel_stream.slave_t;

      out_o : out nsl_video.pixel_stream.master_t;
      out_i : in nsl_video.pixel_stream.slave_t
      );
  end component;

end package;
