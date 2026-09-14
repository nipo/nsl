library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math;

-- What a frame of PCM audio is made of, and what a stream of them
-- runs at.
--
-- A frame is one sample of every channel, taken at the same instant.
-- Channels are numbered in the order the layout names them, so a
-- stereo stream sends left as channel 0 and right as channel 1.
--
-- A sample is right aligned and, when the coding is signed, sign
-- extended: bit zero is the least significant bit whatever the width,
-- and arithmetic on one needs no shift.  A transport carrying samples
-- left justified in a wider field -- HDMI states twenty bit audio in
-- twenty four bits -- is stating a sample of the wider width whose low
-- bits are zero, which is the same number and needs no shift either.
--
-- Alongside a sample a channel may carry sideband bits.  IEC 60958
-- puts three of them next to every sample: V, set when the sample is
-- not linear PCM, U for one bit of the user channel and C for one bit
-- of channel status.  Both U and C take a block of frames to say
-- anything, which is why a block is the unit a stream of these is cut
-- into.
--
-- Parity is not among them.  It guards one transport and is worked out
-- again by the next, so it never crosses a boundary.
--
-- The rate is not part of any of this.  A frame says nothing about
-- when it was taken, and a receiver comes to know the rate by
-- measuring it or by being told out of band -- an HDMI source states N
-- and CTS in a packet of its own, and may change them mid-stream.  So
-- a rate travels beside a stream as a value rather than inside it as a
-- type, and changing rate costs nothing.
package pcm is

  constant max_channel_count_c: natural := 8;
  constant max_sample_bits_c: natural := 32;
  constant max_sideband_bits_c: natural := 8;

  -- How a sample's bits are to be read.  Linear PCM is signed two's
  -- complement nearly everywhere; unsigned turns up in eight bit wave
  -- files.  Companded and floating point samples are not PCM and want
  -- a conversion stage rather than a flag.
  type coding_t is (CODING_SIGNED, CODING_UNSIGNED);

  subtype sample_t is unsigned(max_sample_bits_c-1 downto 0);
  subtype sideband_t is std_ulogic_vector(max_sideband_bits_c-1 downto 0);

  constant sample_zero_c: sample_t := (others => '0');
  constant sideband_zero_c: sideband_t := (others => '0');

  type channel_t is
  record
    sample: sample_t;
    sideband: sideband_t;
  end record;

  -- One frame.  Channel 0 is the one the layout names first.
  type frame_t is array (natural range 0 to max_channel_count_c-1) of channel_t;
  type frame_vector is array (natural range <>) of frame_t;

  constant channel_zero_c: channel_t := (sample => sample_zero_c,
                                         sideband => sideband_zero_c);
  constant frame_zero_c: frame_t := (others => channel_zero_c);

  -- Bytes a sample of this many bits is held in.  Samples sit on byte
  -- boundaries so that a stream written to memory lands on the layout
  -- everything else expects, and so that byte lanes keep meaning
  -- something.
  function sample_bytes(bits: natural) return natural;

  -- Reads a sample out of the field it was held in, which is as wide
  -- as sample_bytes made it.  Signed samples are sign extended, so
  -- what comes back is the same number at the full width.
  function to_sample(field: unsigned; coding: coding_t) return sample_t;

  -- Frames a block of channel status takes.  IEC 60958 sends one bit
  -- of it per frame per channel, so this is how many frames it takes
  -- to say anything with U or C.
  constant block_frame_count_c: natural := 192;

  -- A rate, in frames a second.  Wide enough for anything a link
  -- carries.
  constant max_rate_width_c: natural := 20;
  subtype rate_t is unsigned(max_rate_width_c-1 downto 0);

  function to_rate(hz: natural) return rate_t;

  constant rate_32k_c: rate_t := to_rate(32_000);
  constant rate_44k1_c: rate_t := to_rate(44_100);
  constant rate_48k_c: rate_t := to_rate(48_000);
  constant rate_88k2_c: rate_t := to_rate(88_200);
  constant rate_96k_c: rate_t := to_rate(96_000);
  constant rate_176k4_c: rate_t := to_rate(176_400);
  constant rate_192k_c: rate_t := to_rate(192_000);

end package pcm;

package body pcm is

  function sample_bytes(bits: natural) return natural
  is
  begin
    return (bits + 7) / 8;
  end function;

  function to_sample(field: unsigned; coding: coding_t) return sample_t
  is
  begin
    case coding is
      when CODING_SIGNED =>
        return unsigned(resize(signed(field), max_sample_bits_c));

      when CODING_UNSIGNED =>
        return resize(field, max_sample_bits_c);
    end case;
  end function;

  function to_rate(hz: natural) return rate_t
  is
  begin
    assert hz < 2 ** max_rate_width_c
      report "Rate does not fit"
      severity failure;

    return to_unsigned(hz, max_rate_width_c);
  end function;

end package body pcm;
