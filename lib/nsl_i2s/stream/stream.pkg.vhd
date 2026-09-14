library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_audio;

-- Carries I2S audio as frames on an AXI4-Stream, in the shape
-- nsl_audio.pcm_stream states.
--
-- I2S sends one channel at a time and says which as it goes, so these
-- two put frames together and take them apart again either side of it.
--
-- There is no sideband: I2S carries samples and nothing else, no
-- validity flag, no user channel and no channel status.  A stream
-- either way therefore states no sideband bits, and a block boundary
-- means nothing -- a packet is simply however many frames suit
-- whatever holds them.
package stream is

  -- What a stream carrying I2S looks like: two channels of the width
  -- the wire is clocked for, and nothing beside them.
  function stream_config(
    sample_bits: natural := 24;
    frames_per_packet: natural := nsl_audio.pcm.block_frame_count_c;
    ready: boolean := true) return nsl_audio.pcm_stream.config_t;

  -- Feeds a transmitter from a stream.
  --
  -- A transmitter asks for a word with a pulse one cycle long, so what
  -- is acted on here is the cycle it happens.  A receiver, the other
  -- way round, holds its word up for a whole bit clock, so the one
  -- below acts on the moment that starts instead.  The two are not the
  -- same shape, which is the sort of thing worth stating rather than
  -- discovering.
  --
  -- The transmitter asks for a word at a time and says which channel
  -- it is for; a beat is taken off the stream once its last channel
  -- has gone.  A word asked for with no frame in hand is sent as
  -- whatever the last one held and underflow_o says so: a transmitter
  -- clocked off the wire cannot be told to wait.
  component i2s_stream_transmitter is
    generic(
      config_c : nsl_audio.pcm_stream.config_t
      );
    port(
      reset_n_i : in std_ulogic;
      clock_i : in std_ulogic;

      in_i : in nsl_amba.axi4_stream.master_t;
      in_o : out nsl_amba.axi4_stream.slave_t;

      -- To nsl_i2s.transmitter
      ready_i : in std_ulogic;
      channel_i : in std_ulogic;
      data_o : out unsigned(config_c.sample_bits-1 downto 0);

      underflow_o : out std_ulogic
      );
  end component;

  -- Puts a stream together out of what a receiver takes off the wire.
  --
  -- A frame goes out once every channel of it has arrived.  Packets are
  -- cut to the configured length, and since I2S states no blocks none
  -- is ever marked as one.  A beat not taken before the next frame is
  -- whole is lost, overflow_o says so, and the packet it belonged to is
  -- marked in error when it closes.
  component i2s_stream_receiver is
    generic(
      config_c : nsl_audio.pcm_stream.config_t
      );
    port(
      reset_n_i : in std_ulogic;
      clock_i : in std_ulogic;

      -- From nsl_i2s.receiver
      valid_i : in std_ulogic;
      channel_i : in std_ulogic;
      data_i : in unsigned(config_c.sample_bits-1 downto 0);

      out_o : out nsl_amba.axi4_stream.master_t;
      out_i : in nsl_amba.axi4_stream.slave_t;

      overflow_o : out std_ulogic
      );
  end component;

end package stream;

package body stream is

  function stream_config(
    sample_bits: natural := 24;
    frames_per_packet: natural := nsl_audio.pcm.block_frame_count_c;
    ready: boolean := true) return nsl_audio.pcm_stream.config_t
  is
  begin
    return nsl_audio.pcm_stream.config(
      channels => 2,
      sample_bits => sample_bits,
      sideband_bits => 0,
      coding => nsl_audio.pcm.CODING_SIGNED,
      frames_per_packet => frames_per_packet,
      ready => ready);
  end function;

end package body stream;
