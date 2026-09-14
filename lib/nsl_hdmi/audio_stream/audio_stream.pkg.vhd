library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_audio, work;

-- Carries the audio an HDMI link brought in on an AXI4-Stream, in the
-- shape nsl_audio.pcm_stream states.
--
-- From here on the audio is no longer HDMI's: it is frames on a
-- stream, which a FIFO holds, a width converter narrows, a DMA writes
-- and an I2S or SPDIF transmitter sends, none of them knowing where it
-- came from.
package audio_stream is

  -- What a stream carrying HDMI audio looks like: two channels of
  -- twenty four bits, and the three IEC 60958 bits alongside each.
  --
  -- Twenty four because that is the field HDMI states a sample in
  -- whatever its real width, and a sixteen bit sample in it is a
  -- twenty four bit sample whose low bits are zero.  Narrowing is a
  -- thing to do once something says what the real width is, which the
  -- audio infoframe does and this does not read.
  function stream_config(
    sideband: boolean := true;
    ready: boolean := true) return nsl_audio.pcm_stream.config_t;

  -- Turns what nsl_hdmi.audio.hdmi_audio_receiver hands out into that
  -- stream.
  --
  -- Packets are cut to blocks.  A source states where a block of
  -- channel status begins, and a frame is held back one place so that
  -- the frame before a block start can be the one closing a packet --
  -- a boundary cannot be marked on a beat already gone.  That costs
  -- one frame of latency, which at forty eight kilohertz is twenty
  -- microseconds.
  --
  -- When a block starts somewhere other than where the configured
  -- packet length expected it, the packet closing there is marked in
  -- error rather than quietly handed over short.
  --
  -- There is no back pressure upstream: a receiver takes what the link
  -- sends whether anything downstream is listening or not.  A beat not
  -- taken before the next frame arrives is therefore lost, overflow_o
  -- says so, and the packet it belonged to is marked in error when it
  -- closes.  A FIFO deep enough for a block belongs immediately after
  -- this, since a link delivers frames in bursts inside blanking and
  -- anything downstream will want them evenly.
  component hdmi_audio_stream_source is
    generic(
      config_c : nsl_audio.pcm_stream.config_t
      );
    port(
      reset_n_i : in std_ulogic;
      clock_i : in std_ulogic;

      -- Straight off nsl_hdmi.audio.hdmi_audio_receiver
      valid_i : in std_ulogic;
      a_i, b_i : in work.audio.channel_sample_t;
      block_start_i : in std_ulogic;

      out_o : out nsl_amba.axi4_stream.master_t;
      out_i : in nsl_amba.axi4_stream.slave_t;

      -- A frame was dropped for want of somewhere to put it
      overflow_o : out std_ulogic
      );
  end component;

end package audio_stream;

package body audio_stream is

  function stream_config(
    sideband: boolean := true;
    ready: boolean := true) return nsl_audio.pcm_stream.config_t
  is
    variable sideband_bits: natural;
  begin
    if sideband then
      sideband_bits := 3;
    else
      sideband_bits := 0;
    end if;

    return nsl_audio.pcm_stream.config(
      channels => 2,
      sample_bits => 24,
      sideband_bits => sideband_bits,
      coding => nsl_audio.pcm.CODING_SIGNED,
      ready => ready);
  end function;

end package body audio_stream;
