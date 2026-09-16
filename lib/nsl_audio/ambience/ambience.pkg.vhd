library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_audio, nsl_math;

-- Feedback-based ambience effects.
--
-- The primitive in this package is deliberately an echo rather than a
-- claimed room model: it has one variable frame delay and one feedback
-- path.  Metadata is not fed back.  It follows the frame currently being
-- processed, so delayed audio cannot move packet or channel boundaries.
package ambience is

  -- A variable-delay echo with a single feedback path.
  --
  -- delay_i is measured in accepted PCM frames.  Zero disables the delayed
  -- path; one is the previous accepted frame.  The maximum setting is
  -- 2**max_delay_l2_c - 1 frames.
  --
  -- dry_i, wet_i and feedback_i are non-negative fixed-point gains.  They
  -- are normally supplied in the [0, 1] range, using the fixed-point range
  -- selected by the caller.  The output and feedback writes saturate to the
  -- configured signed sample width.
  --
  -- A reset, or a change on delay_i, flushes the whole delay line.  Input is
  -- backpressured while that happens, and the new delay is only made active
  -- after the flush completes.
  component pcm_echo is
    generic(
      in_config_c : nsl_audio.pcm_stream.config_t;
      out_config_c : nsl_audio.pcm_stream.config_t;
      max_delay_l2_c : natural range 1 to 30 := 10;
      guard_bits_c : natural := 4
      );
    port(
      reset_n_i : in std_ulogic;
      clock_i : in std_ulogic;

      in_i : in nsl_amba.axi4_stream.master_t;
      in_o : out nsl_amba.axi4_stream.slave_t;

      out_o : out nsl_amba.axi4_stream.master_t;
      out_i : in nsl_amba.axi4_stream.slave_t;

      delay_i : in unsigned(max_delay_l2_c-1 downto 0);
      dry_i : in nsl_math.fixed.ufixed;
      wet_i : in nsl_math.fixed.ufixed;
      feedback_i : in nsl_math.fixed.ufixed
      );
  end component;

end package ambience;
