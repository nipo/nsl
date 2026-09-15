library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, work;

-- DVI protocol decoder.
-- Also recovers data islands that are used by HDMI.
package decoder is

  -- Takes the three TMDS channels apart and says what each symbol
  -- period carries, the mirror of
  -- nsl_dvi.encoder.source_stream_encoder.
  --
  -- A symbol cannot be classified on its own: TERC4 words and pixel
  -- data share code points, and guard band symbols decode as pixel
  -- data too.  What tells them apart is where they sit, so the
  -- decoder follows the link through its periods -- preamble, guard
  -- band, then data -- and reports the period the symbols on its
  -- outputs belong to.
  --
  -- The preamble is not counted.  An HDMI source states eight control
  -- periods before a guard band and some state more, so what is
  -- looked for is a preamble followed by a guard band rather than a
  -- preamble of a given length.
  --
  -- A DVI link announces nothing: it has no preamble and no guard
  -- band, and video simply starts on the first symbol that is not a
  -- control one.  Both ways in are followed, so the same decoder
  -- reads either link.
  --
  -- A TERC4 word does not open one, though.  It reads as data rather
  -- than as control, so an island whose preamble went unheard would
  -- otherwise start a video period on its guard band and hold it for
  -- the whole island -- thirty six symbols of packet read as pixels,
  -- with nothing to say so.  A DVI link never sends a TERC4 word, so
  -- the only cost is the odd line whose first pixel happens to encode
  -- as one starting a pixel late.
  --
  -- Nothing else is held against a link.  Shutting that way in
  -- whenever a preamble had been seen was tried and is worse: a lane
  -- taking the odd bit wrong throws a preamble up every so often, and
  -- on a link whose other lanes are not being read well that is often
  -- enough to shut a good picture out most of the time.  What a symbol
  -- is says enough on its own.
  --
  -- Symbols reach the outputs three cycles after the pad, and
  -- everything an output carries belongs to the same symbol period.
  component sink_stream_decoder is
    port(
      reset_n_i : in std_ulogic;
      pixel_clock_i : in std_ulogic;

      tmds_i : in work.dvi.symbol_vector_t;

      period_o: out work.dvi.period_t;

      -- Pixel data, only valid if period_o = PERIOD_VIDEO_DATA
      pixel_o : out nsl_data.bytestream.byte_string(0 to 2);

      -- Syncs.  Only some periods carry them -- video data and guard
      -- bands carry none -- so what comes out is the last one seen,
      -- held across the periods that state nothing.  A raster's syncs
      -- therefore come out whole rather than in pieces.
      hsync_o : out std_ulogic;
      vsync_o : out std_ulogic;

      -- Data island contents, only valid if period_o =
      -- PERIOD_DI_DATA.  di_hdr_o(0) is the header bit this symbol
      -- carries, and di_hdr_o(1) is deasserted on the first symbol of
      -- the island.  Packets are 32 symbols each, so that first
      -- symbol is what packet boundaries are counted from when a
      -- source puts several packets in one island.
      di_hdr_o : out std_ulogic_vector(1 downto 0);
      di_data_o : out std_ulogic_vector(7 downto 0)
      );
  end component;

end package decoder;
