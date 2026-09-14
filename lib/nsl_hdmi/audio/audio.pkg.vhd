library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_spdif, work;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use work.hdmi.all;

-- HDMI Audio data islands, both ways.
package audio is

  function di_audio_clock_regen(cts, n: unsigned(19 downto 0)) return data_island_t;

  -- One channel of one audio frame, as an audio sample packet carries
  -- it: twenty four bits of sample and the three IEC 60958 bits that
  -- ride along with it.
  --
  -- A sample is left justified in its field, so twenty bit audio sits
  -- in the top twenty bits and sixteen bit audio in the top sixteen.
  -- V is set when the sample is *not* linear PCM, which is the way
  -- round IEC 60958 states it.  U is one bit of the user channel and C
  -- one bit of channel status, both of which take a block of frames to
  -- say anything.
  type channel_sample_t is
  record
    data: unsigned(23 downto 0);
    v, u, c: std_ulogic;
  end record;

  component hdmi_spdif_di_encoder is
    generic(
      audio_clock_divisor_c: natural := 4096
      );
    port(
      reset_n_i : in std_ulogic;
      clock_i : in std_ulogic;

      cts_send_i : in std_ulogic;
      cts_i : in unsigned(19 downto 0);

      enable_i : in std_ulogic := '1';

      -- SPDIF block input
      block_ready_o : out std_ulogic;
      block_valid_i : in std_ulogic := '1';
      block_user_i : in std_ulogic_vector(0 to 191);
      block_channel_status_i : in std_ulogic_vector(0 to 191);
      block_channel_status_aesebu_auto_crc_i : in std_ulogic := '0';

      -- PCM data input
      ready_o : out std_ulogic;
      valid_i : in std_ulogic := '1';
      a_i, b_i: in nsl_spdif.blocker.channel_data_t;

      -- HDMI SOF marker from encoder
      sof_i : in std_ulogic := '0';

      -- DI stream
      di_valid_o : out std_ulogic;
      di_ready_i : in std_ulogic;
      di_o : out work.hdmi.data_island_t
      );
  end component;

  -- Takes audio out of the packets an island carried.
  --
  -- Two kinds matter.  An audio sample packet holds up to four frames
  -- of two channels, and which of its four subpackets hold one is in
  -- its header rather than in its length.  An audio clock regeneration
  -- packet holds N and CTS, which is how a sink works out what rate
  -- the samples are meant to come out at -- nothing in the samples
  -- themselves says.
  --
  -- Frames are handed out one a cycle, so a packet takes four cycles
  -- at most to empty.  Packets cannot arrive faster than one every
  -- thirty two, so none is ever dropped for want of room.
  --
  -- A packet whose parity failed is ignored.  A wrong sample is worth
  -- less than no sample, and a wrong N or CTS would pull the clock
  -- for as long as it stood.
  --
  -- Layout 0 only, which is two channels.  A source sends that unless
  -- a sink asked for more in its EDID.
  component hdmi_audio_receiver is
    port(
      reset_n_i : in std_ulogic;
      clock_i : in std_ulogic;

      -- Straight off nsl_hdmi.decoder.data_island_receiver
      valid_i : in std_ulogic;
      error_i : in std_ulogic;
      packet_i : in work.hdmi.data_island_t;

      -- What a source last said about the rate
      acr_valid_o : out std_ulogic;
      cts_o : out unsigned(19 downto 0);
      n_o : out unsigned(19 downto 0);

      -- One frame of two channels
      valid_o : out std_ulogic;
      a_o, b_o : out channel_sample_t;
      -- Whether this frame opens a block of channel status
      block_start_o : out std_ulogic;
      -- Whether the source stated the frame as silence.  The samples
      -- are still handed over, and are zero.
      flat_o : out std_ulogic
      );
  end component;

  -- Makes an audio clock out of the link clock.
  --
  -- A source states N and CTS rather than a rate, and they mean
  -- 128 * fs = link clock * N / CTS.  What comes out here is a tick at
  -- 128 * fs and another at fs, counted rather than generated: an
  -- accumulator takes N every link cycle and gives a tick back every
  -- CTS it holds.
  --
  -- That makes a tick whose average rate is exactly right and whose
  -- spacing is not, wandering by one cycle either way.  Anything
  -- taking these clocks its own way -- I2S out, SPDIF out, a DAC --
  -- retimes them, so the jitter costs nothing.  Driving a converter
  -- straight off one would be another matter.
  component hdmi_audio_clock_recovery is
    port(
      reset_n_i : in std_ulogic;
      clock_i : in std_ulogic;

      -- As the receiver above reports them.  Held between updates, so
      -- valid marks a change rather than a repeat.
      valid_i : in std_ulogic;
      cts_i : in unsigned(19 downto 0);
      n_i : in unsigned(19 downto 0);

      -- Whether a rate has been stated at all.  Nothing ticks before
      -- it has.
      ready_o : out std_ulogic;

      mclk_tick_o : out std_ulogic;
      sample_tick_o : out std_ulogic
      );
  end component;

  component hdmi_spdif_cts_counter is
    generic(
      audio_clock_divisor_c: natural := 4096
      );
    port(
      reset_n_i : in std_ulogic;
      clock_i : in std_ulogic;

      cts_o : out unsigned(19 downto 0);
      cts_send_o : out std_ulogic;

      spdif_tick_i : in std_ulogic
      );
  end component;

end package audio;

package body audio is

  function di_audio_clock_regen(cts, n: unsigned(19 downto 0)) return data_island_t
  is
    variable ret : data_island_t;
    constant tmp: byte_string(0 to 6) := to_be(x"000" & cts & x"0" & n);
  begin
    ret.packet_type := di_type_audio_clock_regen;
    ret.hb := from_hex("0000");
    ret.pb := tmp & tmp & tmp & tmp;
    return ret;
  end function;

end package body;
