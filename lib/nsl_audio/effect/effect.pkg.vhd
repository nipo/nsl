library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library nsl_amba, nsl_data, nsl_math, work;
use nsl_data.bytestream.all;
use nsl_data.endian.all;

-- Things done to audio on its way past.
--
-- Three blocks, which cascaded are a fuzz box: an amplifier, a
-- saturator and a tone control.  They are separate because they are
-- separately useful -- a compressor wants the saturator alone, a
-- mixer wants the amplifier alone -- and because what makes a fuzz a
-- fuzz is not any one of them but the order they come in.
--
-- All three take channels in turn rather than at once.  A frame at
-- forty eight kilohertz is a thousand cycles of a fifty megahertz
-- clock and a channel needs a handful, so sharing one multiplier
-- across eight channels costs latency nobody can hear and saves
-- eight times the arithmetic.  What that means for a caller is that
-- a beat leaves some cycles after it arrived, which a stream says
-- anyway.
--
-- Headroom between blocks is a width, not a scale.  A sample is an
-- integer of sample_bits, so a stream of thirty two bit samples
-- feeding one of twenty four bit samples is stating the same least
-- significant bit with eight more bits above it: full scale is two
-- hundred and fifty six times as far away.  An amplifier that widens
-- its stream therefore has somewhere to put its gain, and the
-- saturator that follows knows how much room it was given by
-- subtracting the two widths.  Nothing has to agree on a scale
-- factor travelling beside the audio.
package effect is

  -- Transfer curve of the saturator, over the input range the table
  -- covers.  All three are odd, monotonic, unity slope near zero
  -- (SHAPE_DIODE excepted, see below) and reach full scale at the top
  -- of the range.
  --
  -- - SHAPE_TANH is the hyperbolic tangent, the smooth one.  What
  --   compression there is starts early and is gradual throughout.
  -- - SHAPE_SOFT_KNEE is a straight line to knee_c and an exponential
  --   approach to full scale beyond it, the two meeting at the same
  --   slope.  Below the knee the signal is untouched, which is what a
  --   stage meant to be clean until it is not wants.
  -- - SHAPE_DIODE is x/(1+x), the algebraic one.  It bends sooner and
  --   flattens later than the others, so it keeps more of what it is
  --   compressing.  Normalising it to reach full scale gives it a
  --   small signal slope of 1.25 rather than 1.
  type shape_t is (SHAPE_TANH, SHAPE_SOFT_KNEE, SHAPE_DIODE);

  -- Bits of a magnitude that fall between two table points, which is
  -- what an interpolation weight is made of.
  function shaper_frac_bits(sample_bits_c, domain_l2_c, table_l2_c: natural)
    return natural;
  -- Bytes one table word takes: a point and the step to the next.
  function shaper_word_bytes(sample_bits_c, domain_l2_c, table_l2_c: natural)
    return natural;
  -- The table itself, worked out at elaboration.
  function shaper_curve(shape_c: shape_t;
                        knee_c: real;
                        sample_bits_c, domain_l2_c, table_l2_c: natural)
    return byte_string;

  -- An amplifier.
  --
  -- Output is input times gain_i, saturated to what the outgoing
  -- stream can hold.  Gain is a port rather than a generic: a knob
  -- turns.
  --
  -- Where the gain is meant to drive something into saturation rather
  -- than to set a level, the outgoing stream wants to be wider than
  -- the incoming one by as many bits as the gain has above unity.
  -- Then nothing is saturated here and the block after decides what
  -- to do about it, which is the whole point of putting a saturator
  -- there.
  component pcm_gain is
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

      gain_i : in nsl_math.fixed.ufixed
      );
  end component;

  -- A saturator.
  --
  -- The curve is a table of 2**table_l2_c points and the step from
  -- each to the next, read once per channel and interpolated between.
  -- Storing the step rather than looking the next point up as well is
  -- what makes one port of one memory enough, and it is also what
  -- keeps the multiplier small: a step is at most a couple of times
  -- the distance between two points, however tall the curve is.
  --
  -- The table spans magnitudes from nothing up to 2**domain_l2_c
  -- times what the outgoing stream calls full scale, and anything
  -- past that comes out at full scale.  The incoming stream must
  -- therefore be at least domain_l2_c bits wider than the outgoing
  -- one, which is the headroom an amplifier before it was given.
  --
  -- The curve is odd: a magnitude is looked up and the sign put back
  -- afterwards.
  component pcm_shaper is
    generic(
      in_config_c : work.pcm_stream.config_t;
      out_config_c : work.pcm_stream.config_t;
      shape_c : shape_t := SHAPE_TANH;
      -- Where the straight part ends, in output full scales.
      -- SHAPE_SOFT_KNEE only.
      knee_c : real := 0.5;
      -- Input range the curve covers, in output full scales
      domain_l2_c : natural := 2;
      -- Points in the table
      table_l2_c : natural := 8
      );
    port(
      reset_n_i : in std_ulogic;
      clock_i : in std_ulogic;

      in_i : in nsl_amba.axi4_stream.master_t;
      in_o : out nsl_amba.axi4_stream.slave_t;

      out_o : out nsl_amba.axi4_stream.master_t;
      out_i : in nsl_amba.axi4_stream.slave_t
      );
  end component;

  -- A tone control.
  --
  -- Two one-pole filters of fixed corner, one taken as it stands and
  -- one subtracted from the signal, mixed by blend_i: nothing but the
  -- lowpass at zero, nothing but the highpass at one.  That is the
  -- tone stack of a fuzz box, where the knob does not move a corner
  -- but fades between two of them, and it is why the middle of the
  -- travel sounds scooped rather than flat.
  --
  -- Corners are stated in hertz against rate_c, the rate the stream
  -- actually runs at, and turn into coefficients at elaboration.  A
  -- stream arriving at another rate is a filter at another corner --
  -- nothing here measures anything.
  --
  -- guard_bits_c is the precision the filter state keeps below the
  -- least significant bit of a sample.  A one-pole filter moves its
  -- state by the error times the coefficient, and when that product
  -- falls under what the state can hold the filter stops short of
  -- where it was going.  The lowest corner asked for is what sets how
  -- many bits it takes; elaboration checks it.
  component pcm_tone is
    generic(
      in_config_c : work.pcm_stream.config_t;
      out_config_c : work.pcm_stream.config_t;
      -- Frames a second the stream is expected to run at
      rate_c : natural := 48000;
      lowpass_hz_c : real := 700.0;
      highpass_hz_c : real := 1500.0;
      guard_bits_c : natural := 8
      );
    port(
      reset_n_i : in std_ulogic;
      clock_i : in std_ulogic;

      in_i : in nsl_amba.axi4_stream.master_t;
      in_o : out nsl_amba.axi4_stream.slave_t;

      out_o : out nsl_amba.axi4_stream.master_t;
      out_i : in nsl_amba.axi4_stream.slave_t;

      blend_i : in nsl_math.fixed.ufixed
      );
  end component;

  -- Coefficient a one-pole filter of this corner needs, as
  -- 1 - exp(-2*pi*fc/fs).
  function one_pole_coefficient(cutoff_hz, rate_hz: real) return real;

end package effect;

package body effect is

  function one_pole_coefficient(cutoff_hz, rate_hz: real) return real
  is
  begin
    return 1.0 - exp(-2.0 * math_pi * cutoff_hz / rate_hz);
  end function;

  function shaper_frac_bits(sample_bits_c, domain_l2_c, table_l2_c: natural)
    return natural
  is
    constant magnitude_bits_c: integer := sample_bits_c - 1 + domain_l2_c;
  begin
    assert magnitude_bits_c > table_l2_c
      report "Saturator table has more points than the magnitudes it indexes"
      severity failure;

    return magnitude_bits_c - table_l2_c;
  end function;

  -- What the curve is worth at x, before being made to reach one.
  function curve_value(shape_c: shape_t; knee_c, x: real) return real
  is
  begin
    case shape_c is
      when SHAPE_TANH =>
        return tanh(x);

      when SHAPE_SOFT_KNEE =>
        if x <= knee_c then
          return x;
        end if;
        return knee_c + (1.0 - knee_c)
          * (1.0 - exp(-(x - knee_c) / (1.0 - knee_c)));

      when SHAPE_DIODE =>
        return x / (1.0 + x);
    end case;
  end function;

  -- Points of the curve, in least significant bits of the outgoing
  -- sample.  Index 2**table_l2_c is the top of the range, which is
  -- where the curve is made to reach full scale.
  function curve_point(shape_c: shape_t;
                       knee_c: real;
                       sample_bits_c, domain_l2_c, table_l2_c: natural;
                       index: natural) return natural
  is
    constant full_c: real := real(2 ** (sample_bits_c - 1) - 1);
    constant top_c: real := real(2 ** domain_l2_c);
    constant x_c: real := top_c * real(index) / real(2 ** table_l2_c);
    constant scale_c: real := full_c / curve_value(shape_c, knee_c, top_c);
  begin
    return natural(round(scale_c * curve_value(shape_c, knee_c, x_c)));
  end function;

  function shaper_delta_bits(sample_bits_c, domain_l2_c, table_l2_c: natural)
    return natural
  is
  begin
    return shaper_frac_bits(sample_bits_c, domain_l2_c, table_l2_c) + 2;
  end function;

  function shaper_word_bytes(sample_bits_c, domain_l2_c, table_l2_c: natural)
    return natural
  is
    constant bits_c: natural := sample_bits_c - 1
      + shaper_delta_bits(sample_bits_c, domain_l2_c, table_l2_c);
  begin
    return (bits_c + 7) / 8;
  end function;

  function shaper_curve(shape_c: shape_t;
                        knee_c: real;
                        sample_bits_c, domain_l2_c, table_l2_c: natural)
    return byte_string
  is
    constant value_bits_c: natural := sample_bits_c - 1;
    constant delta_bits_c: natural
      := shaper_delta_bits(sample_bits_c, domain_l2_c, table_l2_c);
    constant word_bits_c: natural
      := 8 * shaper_word_bytes(sample_bits_c, domain_l2_c, table_l2_c);
    variable ret: byte_string(0 to shaper_word_bytes(sample_bits_c, domain_l2_c, table_l2_c)
                              * (2 ** table_l2_c) - 1);
    variable word: unsigned(word_bits_c-1 downto 0);
    variable here, above, delta: natural;
    variable base: natural;
  begin
    for i in 0 to 2 ** table_l2_c - 1
    loop
      here := curve_point(shape_c, knee_c, sample_bits_c, domain_l2_c,
                          table_l2_c, i);
      above := curve_point(shape_c, knee_c, sample_bits_c, domain_l2_c,
                           table_l2_c, i + 1);

      assert above >= here
        report "Saturator curve is not monotonic"
        severity failure;

      delta := above - here;

      assert delta < 2 ** delta_bits_c
        report "Saturator curve rises too steeply for the table to state"
        severity failure;

      word := (others => '0');
      word(value_bits_c-1 downto 0) := to_unsigned(here, value_bits_c);
      word(value_bits_c+delta_bits_c-1 downto value_bits_c)
        := to_unsigned(delta, delta_bits_c);

      base := i * (word_bits_c / 8);
      ret(base to base + word_bits_c/8 - 1) := to_le(word);
    end loop;

    return ret;
  end function;

end package body effect;
