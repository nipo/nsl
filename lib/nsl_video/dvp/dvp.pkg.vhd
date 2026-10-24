library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_video;

-- Digital Video Port, the parallel output of most CMOS image
-- sensors: a pixel clock, a byte-wide data bus, a frame sync and a
-- line valid (HREF).
package dvp is

  -- Receives a DVP bus in its own pixel clock domain and pairs bytes
  -- into 16-bit words, first byte of a line in the upper half.  This
  -- matches 16-bit sensor formats (RGB565, YUV422) where a pixel, or
  -- a pair of components, spans two bus cycles.
  --
  -- Bus is sampled on rising edge of pclk_i.  Sensors driving the
  -- bus on rising edge need their PCLK polarity inverted.
  --
  -- sof_o flags the first word after a frame sync, sol_o the first
  -- word of each line.  A line holding an odd byte count loses its
  -- last byte.  There is no backpressure: whatever takes words has
  -- to absorb them as they come.
  component dvp_receiver is
    generic(
      -- Level of vsync_i during frame sync.
      vsync_active_c: std_ulogic := '1';
      -- Level of href_i while line data is valid.
      href_active_c: std_ulogic := '1'
      );
    port(
      pclk_i: in std_ulogic;
      reset_n_i: in std_ulogic;

      vsync_i: in std_ulogic;
      href_i: in std_ulogic;
      data_i: in std_ulogic_vector(7 downto 0);

      valid_o: out std_ulogic;
      sof_o: out std_ulogic;
      sol_o: out std_ulogic;
      data_o: out std_ulogic_vector(15 downto 0)
      );
  end component;

  -- What a 16-bit word from dvp_receiver holds.
  --
  -- - RGB565: one pixel, R in bits 15..11, G in 10..5, B in 4..0,
  --   i.e. a sensor sending the high byte first.
  -- - YCBCR422: one pixel, luma and the chroma component of its
  --   position along the line.  Not implemented yet.
  type format_t is (
    FORMAT_RGB565,
    FORMAT_YCBCR422
    );

  -- Turns words from dvp_receiver into a pixel stream, one pixel a
  -- beat, in the same clock domain.
  --
  -- A DVP bus says where frames and lines start, never where they
  -- end, and not how big they are.  So the geometry is stated here,
  -- and the bus is checked against it:
  --
  -- - a line longer than the geometry is cropped, so are lines past
  --   the frame height,
  -- - a line shorter than the geometry is closed with ERROR,
  -- - a frame cut short, by a new frame starting before its last line
  --   is complete, has the beat closing its last line carry EOF and
  --   ERROR,
  -- - words before the first frame start, as seen after reset, are
  --   dropped.
  --
  -- Every frame let out therefore closes with EOF, and a frame that
  -- came through whole is one with no ERROR on any of its lines.
  --
  -- Telling a line is over takes the next one starting, so a pixel
  -- is held until the next word arrives.  TLAST of a line comes out
  -- with the first word of the next line, except for the last line of
  -- a frame, which closes as soon as its last pixel is in.  A frame
  -- cut short closes with the first word of the frame that follows.
  --
  -- The sensor cannot be held back.  When the stream carries a ready
  -- and the beat on offer is not taken in time for the next one, the
  -- frame is aborted: the pixel held closes the current line with EOF
  -- and ERROR, the rest of the frame is dropped up to the next frame
  -- start, and overflow_o pulses with the word that found no room.
  -- Feeding a FIFO that has room for a burst of beats makes this a
  -- non-event.  A stream with no ready never overflows.
  --
  -- config_c must state one pixel a beat.  An RGB565 word goes out
  -- either as is, into an RGB565 stream, or unpacked into an RGB
  -- stream.  When unpacking, components narrower or wider than what
  -- the word packs are rescaled by bit replication, so full scale
  -- stays full scale.
  component dvp_to_pixel_stream is
    generic(
      config_c: nsl_video.pixel_stream.config_t;
      format_c: format_t := FORMAT_RGB565;
      geometry_c: nsl_video.mode.geometry_t
      );
    port(
      clock_i: in std_ulogic;
      reset_n_i: in std_ulogic;

      -- From dvp_receiver
      valid_i: in std_ulogic;
      sof_i: in std_ulogic;
      sol_i: in std_ulogic;
      data_i: in std_ulogic_vector(15 downto 0);

      out_o: out nsl_video.pixel_stream.master_t;
      out_i: in nsl_video.pixel_stream.slave_t;

      overflow_o: out std_ulogic
      );
  end component;

end package;
