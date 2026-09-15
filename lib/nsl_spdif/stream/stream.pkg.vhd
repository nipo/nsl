library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_audio, work;

-- Carries what an IEC 60958 link holds as frames on an AXI4-Stream, in
-- the shape nsl_audio.pcm_stream states.
--
-- These two sit at the framing layer rather than the blocking one, so
-- what they carry is every bit a subframe holds: the sample, and the
-- V, U and C beside it.  Nothing is interpreted and nothing is thrown
-- away, so a link read in one side and written out the other comes
-- back as it went -- which is what forwarding one needs.
--
-- Parity is the exception.  It guards one link and is worked out again
-- for the next, so it does not travel; what it found is reported
-- instead, as a packet marked in error.
--
-- Getting at the audio, or putting a link together out of audio from
-- somewhere else, is nsl_audio.metadata's pair of adapters: they take
-- the bits off a stream of this shape and put them back.  Reading
-- channel status means waiting for a block of it either way, which is
-- why it is a separate step rather than something these do.
--
-- Both ends of the framer state themselves in one cycle -- a
-- transmitter is asked for a frame with a pulse and a receiver offers
-- one with a pulse -- unlike nsl_i2s, where a receiver holds its word
-- up for a whole bit clock.
package stream is

  -- Samples with the bits IEC 60958 sends beside them.  Packets are
  -- blocks, because that is what U and C need.
  function framed_config(
    ready: boolean := true) return nsl_audio.pcm_stream.config_t;

  -- Samples alone, for once the bits have been taken off.
  function stream_config(
    frames_per_packet: natural := nsl_audio.pcm.block_frame_count_c;
    ready: boolean := true) return nsl_audio.pcm_stream.config_t;

  -- Puts a stream together out of what an unframer takes off the wire.
  --
  -- A frame is held back one place, since a link states where a block
  -- begins and the frame closing a packet is the one before that -- a
  -- boundary cannot be marked on a beat already gone.
  --
  -- An unframer cannot be told to wait, so a beat not taken before the
  -- next frame is whole is lost, overflow_o says so, and the packet it
  -- belonged to is marked when it closes.  So is a packet any frame of
  -- which arrived with its parity broken.
  component spdif_stream_receiver is
    generic(
      config_c : nsl_audio.pcm_stream.config_t
      );
    port(
      reset_n_i : in std_ulogic;
      clock_i : in std_ulogic;

      -- Straight off nsl_spdif.framer.spdif_unframer
      valid_i : in std_ulogic;
      block_start_i : in std_ulogic;
      channel_i : in std_ulogic;
      frame_i : in work.framer.frame_t;
      parity_ok_i : in std_ulogic := '1';

      out_o : out nsl_amba.axi4_stream.master_t;
      out_i : in nsl_amba.axi4_stream.slave_t;

      overflow_o : out std_ulogic
      );
  end component;

  -- Feeds a framer from a stream.
  --
  -- The framer asks for one subframe at a time and is told which
  -- channel it is and whether a block starts there, both of which come
  -- from the packet the beat sits in.  A subframe asked for with no
  -- beat in hand is sent as whatever the last one held and underflow_o
  -- says so: a link clocked off its own oscillator cannot be told to
  -- wait.
  component spdif_stream_transmitter is
    generic(
      config_c : nsl_audio.pcm_stream.config_t
      );
    port(
      reset_n_i : in std_ulogic;
      clock_i : in std_ulogic;

      in_i : in nsl_amba.axi4_stream.master_t;
      in_o : out nsl_amba.axi4_stream.slave_t;

      -- To nsl_spdif.framer.spdif_framer
      ready_i : in std_ulogic;
      block_start_o : out std_ulogic;
      channel_o : out std_ulogic;
      frame_o : out work.framer.frame_t;

      underflow_o : out std_ulogic
      );
  end component;

end package stream;

package body stream is

  function framed_config(
    ready: boolean := true) return nsl_audio.pcm_stream.config_t
  is
  begin
    return nsl_audio.metadata.framed_config(
      channels => 2,
      sample_bits => 24,
      ready => ready);
  end function;

  function stream_config(
    frames_per_packet: natural := nsl_audio.pcm.block_frame_count_c;
    ready: boolean := true) return nsl_audio.pcm_stream.config_t
  is
  begin
    return nsl_audio.metadata.plain_config(
      channels => 2,
      sample_bits => 24,
      frames_per_packet => frames_per_packet,
      ready => ready);
  end function;

end package body stream;
