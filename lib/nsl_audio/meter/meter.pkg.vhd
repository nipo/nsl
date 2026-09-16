library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, work;

-- Watching audio go past.
--
-- A meter takes no part in a handshake and never holds a beat up: it
-- is handed the two halves of a stream as they are exchanged and
-- reads what crosses.  Inserting it therefore costs nothing, and
-- forgetting to connect it costs nothing either, which is what one
-- wants of something whose whole purpose is to be looked at.
package meter is

  subtype peak_t is unsigned(work.pcm.max_sample_bits_c-1 downto 0);
  type peak_vector is array (natural range <>) of peak_t;

  -- How loud each channel has lately been.
  --
  -- The magnitude of every sample is taken, and what is shown is the
  -- largest one seen recently: it rises the instant a sample does and
  -- falls away afterwards by one part in 2**decay_l2_c a frame, which
  -- halves it in some seven tenths of that many frames.
  -- That is a peak meter rather than an average one -- it says what
  -- the loudest thing was, which is what matters when the question is
  -- whether something is being clipped.
  --
  -- The fall stops at 2**decay_l2_c, below which a halving would not
  -- change anything, so a reading under that is shown as nothing at
  -- all.  With the default that is some sixty decibels below full
  -- scale of a twenty four bit sample.
  --
  -- What comes out is a magnitude of config_c.sample_bits bits, right
  -- aligned.  A stream wider than what is being measured against --
  -- an amplifier's output, headroom and all -- reads above its own
  -- full scale, which is how far into clipping something is being
  -- driven.
  component pcm_peak_meter is
    generic(
      config_c : work.pcm_stream.config_t;
      decay_l2_c : natural := 12
      );
    port(
      reset_n_i : in std_ulogic;
      clock_i : in std_ulogic;

      -- The stream as it is exchanged, watched rather than carried
      master_i : in nsl_amba.axi4_stream.master_t;
      slave_i : in nsl_amba.axi4_stream.slave_t;

      peak_o : out peak_vector(0 to config_c.channel_count-1)
      );
  end component;

end package meter;
