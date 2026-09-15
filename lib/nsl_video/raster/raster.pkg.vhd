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

  -- Turns a raster arriving on its own schedule into a pixel stream.
  --
  -- Where the other two ways in ask a generator for pixels, this one
  -- is handed them: a raster coming off a wire cannot be asked to
  -- wait, and neither can the stream it turns into, so the stream
  -- carries no ready and whatever takes it has to absorb it.
  --
  -- A pixel is held for a cycle, because what says it closes a line is
  -- that no pixel follows it.  What says it closes a frame is the line
  -- it sits on being the last, which no look at the raster can tell:
  -- it takes knowing how many lines the frame holds.  So the
  -- measurement comes in here, and nothing goes out until it settled
  -- -- which also keeps frames seen while the link was still coming
  -- up from being passed on.  It states the sync polarity too.
  --
  -- A line that does not come out the length the measurement states
  -- is marked in error on the beat that closes it.
  component pixel_stream_capturer is
    generic(
      config_c: nsl_video.pixel_stream.config_t
      );
    port(
      clock_i: in std_ulogic;
      reset_n_i: in std_ulogic;

      de_i: in std_ulogic;
      vsync_i: in std_ulogic;
      pixel_i: in nsl_video.pixel_stream.pixel_t;

      timings_i: in nsl_video.mode.timings_t;
      timings_valid_i: in std_ulogic;

      out_o: out nsl_video.pixel_stream.master_t;
      -- Unused: the stream carries no ready.  Here so a stream is
      -- wired as a pair, as everywhere else.
      out_i: in nsl_video.pixel_stream.slave_t
      );
  end component;

  -- Makes a smaller raster out of a bigger one, by leaving pixels out.
  --
  -- Nothing is filtered and nothing is averaged: one pixel in so many
  -- is kept and the rest are dropped.  That is what a thumbnail on a
  -- small panel wants and what costs nothing -- no line store, no
  -- multiplier, one adder an axis.
  --
  -- Which ones are kept is the remainder trick: an accumulator takes
  -- the output size every pixel and gives a pixel back every input
  -- size it holds.  Over a line that keeps exactly the output width,
  -- wherever the ratio falls -- 1280 to 160 is every eighth pixel and
  -- 1920 to 80 lines is every thirteenth or fourteenth by turns.
  --
  -- The accumulator is tested against the difference of the two sizes
  -- rather than having the step added before the test, so what runs
  -- is one comparison and one addition of a constant rather than two
  -- additions one after the other.
  --
  -- The last pixel of a line always survives, and so does the last
  -- line of a frame, so a line and a frame end where they ended.  The
  -- first does not: the first pixel kept is some way in, which shows
  -- as the picture being cropped by less than one output pixel.
  --
  -- What arrives cannot be held up -- a raster off a wire never can --
  -- so a beat with nowhere to go is dropped and overflow_o says so.
  -- What leaves may be: this is where a captured stream gets its back
  -- pressure back, which is why the two configurations are stated
  -- separately.  They differ in that and in nothing else.
  component pixel_stream_decimator is
    generic(
      in_config_c: nsl_video.pixel_stream.config_t;
      out_config_c: nsl_video.pixel_stream.config_t;
      in_geometry_c: nsl_video.mode.geometry_t;
      out_geometry_c: nsl_video.mode.geometry_t
      );
    port(
      clock_i: in std_ulogic;
      reset_n_i: in std_ulogic;

      in_i: in nsl_video.pixel_stream.master_t;
      in_o: out nsl_video.pixel_stream.slave_t;

      out_o: out nsl_video.pixel_stream.master_t;
      out_i: in nsl_video.pixel_stream.slave_t;

      overflow_o: out std_ulogic
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

  -- Measures the raster a link is sending from its syncs alone.
  --
  -- A sync is asserted where it sits away from the level it holds
  -- while the raster is active, which is what gives its polarity
  -- without being told: no sync is ever asserted during active video.
  --
  -- Horizontal timings are taken from lines that showed pixels, since
  -- a blanking line measures a line that is not the one being looked
  -- for.  Vertical timings are counted in lines.
  --
  -- valid_o is asserted once a frame measured the same as the one
  -- before it, which is what tells a settled link from one still
  -- coming up, or from noise.  Counters stop at the top rather than
  -- wrapping, so a period that never ends measures something no
  -- second frame can agree with.
  --
  -- Nothing about the syncs says what rate they arrive at, so no
  -- clock comes out of here.
  component raster_measurer is
    port(
      clock_i: in std_ulogic;
      reset_n_i: in std_ulogic;

      de_i: in std_ulogic;
      hsync_i: in std_ulogic;
      vsync_i: in std_ulogic;

      timings_o: out nsl_video.mode.timings_t;
      valid_o: out std_ulogic
      );
  end component;

end package;
