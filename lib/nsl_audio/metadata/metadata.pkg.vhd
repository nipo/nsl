library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, work;

-- Takes the bits that ride beside samples off a stream, and puts them
-- back.
--
-- A transport that states V, U and C carries them a bit at a time, and
-- two of the three say nothing until a whole block of them has
-- arrived.  There are two things one may want to do with such a
-- stream, and they pull in opposite directions:
--
-- - forward it as it stands, in which case the bits should stay where
--   they are and never be looked at,
-- - do something with the audio, in which case the samples want to be
--   nothing but samples and the bits want to be whole words somewhere
--   a register can read them.
--
-- Taking apart and putting back together are exact inverses in what
-- they carry, but not in time: a block is not whole until its last
-- frame has gone by, so feeding one straight into the other puts a
-- block of metadata against the frames of the block after it.
--
-- Where that matters, a FIFO a packet deep on the samples brings the
-- two back level, the bits going round it while the samples go
-- through.  That is a plain AXI4-Stream FIFO and knows nothing about
-- audio, which is the whole point of a stream being a stream.
--
-- So there are two shapes of stream and a pair of blocks between them.
-- A stream carrying the bits has sideband and its packets are blocks;
-- one carrying only samples has neither, and may be cut wherever
-- suits.  Extracting and merging are exact inverses, so a stream taken
-- apart and put back together again is the stream that went in.
--
-- The cost of that is registers: a block of three bits for every
-- channel, twice over in the extracting direction so that what is
-- handed out stays still while the next block arrives.  For two
-- channels that is some two thousand of them, which is worth paying
-- once and not at all on a path that only forwards.
package metadata is

  -- Samples with the bits beside them, packets cut to blocks
  function framed_config(
    channels: natural := 2;
    sample_bits: natural := 24;
    ready: boolean := true) return work.pcm_stream.config_t;

  -- The same samples, with nothing beside them
  function plain_config(
    channels: natural := 2;
    sample_bits: natural := 24;
    frames_per_packet: natural := work.pcm.block_frame_count_c;
    ready: boolean := true) return work.pcm_stream.config_t;

  -- Which sideband bit is which, in the order IEC 60958 sends them
  constant sideband_v_c: natural := 0;
  constant sideband_u_c: natural := 1;
  constant sideband_c_c: natural := 2;

  -- Strips the bits off, and gathers them into whole blocks.
  --
  -- Samples pass straight through: the beat leaving carries what the
  -- beat arriving carried, in the same cycle, so nothing is buffered
  -- and nothing is delayed.  Only TUSER differs.
  --
  -- block_valid_o marks the cycle a block became whole.  What is
  -- handed out then stays still until the next one does, so a reader
  -- has a block's worth of time to take it -- four milliseconds at
  -- forty eight kilohertz.
  --
  -- A packet arriving shorter or longer than a block is passed on, and
  -- the block it would have made is not offered: the bits in it do not
  -- line up with anything.
  component pcm_metadata_extract is
    generic(
      in_config_c : work.pcm_stream.config_t;
      out_config_c : work.pcm_stream.config_t
      );
    port(
      reset_n_i : in std_ulogic;
      clock_i : in std_ulogic;

      in_i : in nsl_amba.axi4_stream.master_t;
      in_o : out nsl_amba.axi4_stream.slave_t;

      out_o : out nsl_amba.axi4_stream.master_t;
      out_i : in nsl_amba.axi4_stream.slave_t;

      block_valid_o : out std_ulogic;
      v_o, u_o, c_o : out work.pcm.block_bits_vector(0 to in_config_c.channel_count-1)
      );
  end component;

  -- Puts them back, a bit a frame.
  --
  -- The block to send is taken when block_valid_i says there is one and
  -- a packet is about to start; what is in hand is sent again when
  -- there is nothing new, so a stream never stalls for want of
  -- metadata.  Packets are cut to blocks whatever the stream arriving
  -- was cut to, since that is what the bits need.
  component pcm_metadata_merge is
    generic(
      in_config_c : work.pcm_stream.config_t;
      out_config_c : work.pcm_stream.config_t
      );
    port(
      reset_n_i : in std_ulogic;
      clock_i : in std_ulogic;

      in_i : in nsl_amba.axi4_stream.master_t;
      in_o : out nsl_amba.axi4_stream.slave_t;

      out_o : out nsl_amba.axi4_stream.master_t;
      out_i : in nsl_amba.axi4_stream.slave_t;

      block_valid_i : in std_ulogic := '0';
      block_ready_o : out std_ulogic;
      v_i, u_i, c_i : in work.pcm.block_bits_vector(0 to out_config_c.channel_count-1)
      );
  end component;

end package metadata;

package body metadata is

  function framed_config(
    channels: natural := 2;
    sample_bits: natural := 24;
    ready: boolean := true) return work.pcm_stream.config_t
  is
  begin
    return work.pcm_stream.config(
      channels => channels,
      sample_bits => sample_bits,
      sideband_bits => 3,
      coding => work.pcm.CODING_SIGNED,
      frames_per_packet => work.pcm.block_frame_count_c,
      ready => ready);
  end function;

  function plain_config(
    channels: natural := 2;
    sample_bits: natural := 24;
    frames_per_packet: natural := work.pcm.block_frame_count_c;
    ready: boolean := true) return work.pcm_stream.config_t
  is
  begin
    return work.pcm_stream.config(
      channels => channels,
      sample_bits => sample_bits,
      sideband_bits => 0,
      coding => work.pcm.CODING_SIGNED,
      frames_per_packet => frames_per_packet,
      ready => ready);
  end function;

end package body metadata;
