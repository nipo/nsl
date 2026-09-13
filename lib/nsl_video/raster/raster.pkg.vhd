library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_video;

-- Raster scanning helpers.
--
-- A pixel stream states its own framing, so whatever feeds one has
-- to know where in the frame it is. These components own that
-- position so a frame generator only has to answer what colour sits
-- at a coordinate.
package raster is

  -- Walks the pixels of a frame in raster order, left to right then
  -- top to bottom, and states where it stands.
  --
  -- Position advances on every accepted beat, and wraps back to the
  -- first pixel of the frame after the last one. A beat holds
  -- pixel_count_c pixels starting at x_o; when a line does not hold
  -- a whole number of beats, keep_o clears the pixels of the last
  -- beat that fall past its end.
  --
  -- Deasserting enable_i stops the walk after the beat closing the
  -- current frame, so a stream never stops mid-frame.
  component raster_counter is
    generic(
      geometry_c: nsl_video.mode.geometry_t;
      pixel_count_c: positive := 1
      );
    port(
      clock_i: in std_ulogic;
      reset_n_i: in std_ulogic;

      enable_i: in std_ulogic := '1';

      -- Coordinates of the first pixel of the beat on offer.
      x_o: out unsigned(nsl_video.mode.x_width(geometry_c)-1 downto 0);
      y_o: out unsigned(nsl_video.mode.y_width(geometry_c)-1 downto 0);

      -- Beat on offer holds the first pixel of a frame.
      sof_o: out std_ulogic;
      -- Beat on offer holds the last pixel of a line.
      eol_o: out std_ulogic;
      -- Beat on offer holds the last pixel of a frame.
      eof_o: out std_ulogic;
      -- Pixels of the beat that fall inside the line.
      keep_o: out std_ulogic_vector(0 to pixel_count_c-1);

      valid_o: out std_ulogic;
      ready_i: in std_ulogic
      );
  end component;

  -- Turns what a frame generator makes into a pixel stream.
  --
  -- Owns the scan position, so a generator only has to answer what
  -- colour sits at x_o, y_o.  pixel_i is taken combinatorially into
  -- the beat on offer: a generator that answers with latency has to
  -- run the position through its own pipeline instead.
  component pixel_stream_framer is
    generic(
      geometry_c: nsl_video.mode.geometry_t;
      config_c: nsl_video.pixel_stream.config_t
      );
    port(
      clock_i: in std_ulogic;
      reset_n_i: in std_ulogic;

      enable_i: in std_ulogic := '1';

      x_o: out unsigned(nsl_video.mode.x_width(geometry_c)-1 downto 0);
      y_o: out unsigned(nsl_video.mode.y_width(geometry_c)-1 downto 0);
      pixel_i: in nsl_video.pixel_stream.pixel_vector(0 to config_c.pixel_count-1);
      -- Beat on offer is taken this cycle.  A generator holding its
      -- own state advances it here.
      taken_o: out std_ulogic;

      out_o: out nsl_video.pixel_stream.master_t;
      out_i: in nsl_video.pixel_stream.slave_t
      );
  end component;

  -- Turns what a frame generator makes into a pixel stream, asking
  -- for one pixel at a time.
  --
  -- Where pixel_stream_framer states a coordinate and takes the
  -- colour there in the same cycle, this one states that a frame and
  -- a line open, then asks for pixels and waits for each.  That is
  -- what a generator reading a memory needs: it answers late, and
  -- nothing downstream has taken anything meanwhile, so a late
  -- answer costs time rather than position.
  --
  -- A stream has no blanking to state framing in, so sof_o and sol_o
  -- take a cycle of their own before the first pixel of what they
  -- open is asked for.
  component pixel_stream_requester is
    generic(
      geometry_c: nsl_video.mode.geometry_t;
      config_c: nsl_video.pixel_stream.config_t
      );
    port(
      clock_i: in std_ulogic;
      reset_n_i: in std_ulogic;

      enable_i: in std_ulogic := '1';

      sof_o: out std_ulogic;
      sol_o: out std_ulogic;
      -- A pixel is taken this cycle.
      ready_o: out std_ulogic;
      valid_i: in std_ulogic := '1';
      pixel_i: in nsl_video.pixel_stream.pixel_t;

      out_o: out nsl_video.pixel_stream.master_t;
      out_i: in nsl_video.pixel_stream.slave_t
      );
  end component;

  -- Feeds a raster that owns its own timing from a pixel stream.
  --
  -- Framing travels with the pixels, and a wire-side raster cannot
  -- wait, so the two have to be brought together: the unframer
  -- throws stream beats away until one opens a frame, holds it until
  -- the raster opens a frame of its own, and only then starts
  -- handing pixels over.
  --
  -- From there it checks the two agree.  A line or a frame the
  -- raster opens while the stream has not closed the previous one
  -- shifts everything that follows, so it drops sync and the next
  -- frame starts over.  synced_o states whether pixels are currently
  -- going through.
  --
  -- Getting back in step after that is the hard part when the raster
  -- can wait, because such a raster opens its next frame only once it
  -- has finished this one, and it cannot finish without pixels.  So
  -- one standing still and asking for a pixel is given one, wherever
  -- in its frame it stands: a frame arriving out of step is put right
  -- at the next boundary, whereas holding out for a boundary that
  -- cannot arrive leaves it dark for good.
  --
  -- A raster takes one pixel per cycle, so the stream holds one
  -- pixel per beat.
  --
  -- raster_can_wait_c states whether the raster survives asking for
  -- a pixel and not getting one.  A panel driver does, and simply
  -- holds its serial interface; a wire raster does not, and losing a
  -- pixel there shifts the rest of the frame.
  component pixel_stream_unframer is
    generic(
      config_c: nsl_video.pixel_stream.config_t;
      raster_can_wait_c: boolean := false
      );
    port(
      clock_i: in std_ulogic;
      reset_n_i: in std_ulogic;

      in_i: in nsl_video.pixel_stream.master_t;
      in_o: out nsl_video.pixel_stream.slave_t;

      -- Raster opens a frame, and opens a line.  Both are stated
      -- before the first pixel of what they open is asked for.
      sof_i: in std_ulogic;
      sol_i: in std_ulogic;
      -- Raster takes a pixel.
      ready_i: in std_ulogic;
      valid_o: out std_ulogic;
      pixel_o: out nsl_video.pixel_stream.pixel_t;

      synced_o: out std_ulogic
      );
  end component;

end package;
