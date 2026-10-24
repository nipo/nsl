library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_video;

-- Conversions between pixel stream colorspaces.
package colorspace is

  -- Unpacks an RGB565 stream into an RGB one.
  --
  -- Input configuration is RGB565, output configuration is RGB with
  -- any component width.  Components are rescaled by bit
  -- replication, so full scale stays full scale.  Both carry one
  -- pixel a beat.
  --
  -- A beat takes one cycle to go through, a full rate stream goes
  -- through without bubbles, and framing travels with its pixel.
  component rgb565_unpacker is
    generic(
      in_config_c : nsl_video.pixel_stream.config_t;
      out_config_c : nsl_video.pixel_stream.config_t
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      in_i : in nsl_video.pixel_stream.master_t;
      in_o : out nsl_video.pixel_stream.slave_t;

      out_o : out nsl_video.pixel_stream.master_t;
      out_i : in nsl_video.pixel_stream.slave_t
      );
  end component;

end package colorspace;
