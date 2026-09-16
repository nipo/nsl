library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_audio, nsl_data, nsl_math, nsl_simulation;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_audio.pcm.all;
use nsl_audio.pcm_stream.all;
use nsl_audio.effect.all;
use nsl_data.text.all;
use nsl_math.fixed.all;

-- Puts audio through an amplifier, a saturator and a tone control.
--
-- What is checked of each is what it promises rather than what it
-- happens to compute: that the amplifier multiplies and stops at the
-- rail, that the saturator is odd, rising and bounded and leaves a
-- quiet signal alone, and that the tone control passes what a
-- lowpass passes at one end of its travel and what a highpass passes
-- at the other.
--
-- Two channels throughout, because these take channels in turn and a
-- second one is what shows the turns are taken in the right order.
entity tb is
end entity;

architecture arch of tb is

  constant sample_bits_c: natural := 24;
  constant headroom_bits_c: natural := 8;
  constant wide_bits_c: natural := sample_bits_c + headroom_bits_c;
  constant rate_c: natural := 48000;

  constant narrow_c: config_t := nsl_audio.metadata.plain_config(
    channels => 2, sample_bits => sample_bits_c);
  constant wide_c: config_t := nsl_audio.metadata.plain_config(
    channels => 2, sample_bits => wide_bits_c);

  constant full_scale_c: integer := 2 ** (sample_bits_c-1) - 1;

  -- Curve tables of every shape, built the way a saturator builds
  -- its own.  Declaring them is what runs the checks inside the
  -- builder -- a curve that fell back or rose faster than a word can
  -- state would stop elaboration here -- and what is walked below is
  -- what a saturator would have read.
  constant domain_l2_c: natural := 2;
  constant table_l2_c: natural := 8;
  constant curve_bytes_c: natural
    := shaper_word_bytes(sample_bits_c, domain_l2_c, table_l2_c);
  constant curve_values_c: natural := sample_bits_c - 1;
  constant curve_deltas_c: natural
    := shaper_frac_bits(sample_bits_c, domain_l2_c, table_l2_c) + 2;

  constant tanh_curve_c: byte_string
    := shaper_curve(SHAPE_TANH, 0.5, sample_bits_c, domain_l2_c, table_l2_c);
  constant knee_curve_c: byte_string
    := shaper_curve(SHAPE_SOFT_KNEE, 0.4, sample_bits_c, domain_l2_c,
                    table_l2_c);
  constant diode_curve_c: byte_string
    := shaper_curve(SHAPE_DIODE, 0.5, sample_bits_c, domain_l2_c, table_l2_c);

  signal clock_s, reset_n_s: std_ulogic;
  signal done_s: std_ulogic_vector(0 to 0);

  signal amp_in_m_s, amp_out_m_s: nsl_amba.axi4_stream.master_t;
  signal amp_in_s_s, amp_out_s_s: nsl_amba.axi4_stream.slave_t;
  signal gain_s: ufixed(7 downto -8);

  signal rail_in_m_s, rail_out_m_s: nsl_amba.axi4_stream.master_t;
  signal rail_in_s_s, rail_out_s_s: nsl_amba.axi4_stream.slave_t;

  signal shaper_in_m_s, shaper_out_m_s: nsl_amba.axi4_stream.master_t;
  signal shaper_in_s_s, shaper_out_s_s: nsl_amba.axi4_stream.slave_t;

  signal tone_in_m_s, tone_out_m_s: nsl_amba.axi4_stream.master_t;
  signal tone_in_s_s, tone_out_s_s: nsl_amba.axi4_stream.slave_t;
  signal blend_s: ufixed(0 downto -8);

  -- A sample holding this number, at this width
  function sample_of(v: integer; bits: natural) return sample_t
  is
  begin
    return to_sample(unsigned(to_signed(v, bits)), CODING_SIGNED);
  end function;

  -- A frame of two channels holding these two numbers
  function frame_of(a, b: integer; bits: natural) return frame_t
  is
    variable ret: frame_t := frame_zero_c;
  begin
    ret(0).sample := sample_of(a, bits);
    ret(1).sample := sample_of(b, bits);
    return ret;
  end function;

  -- The number a channel of a frame holds
  function number_of(f: frame_t; channel, bits: natural) return integer
  is
  begin
    return to_integer(signed(f(channel).sample(bits-1 downto 0)));
  end function;

  -- Walks a curve as a saturator reads it: every word holds a point
  -- and the step from there to the next, so following the steps must
  -- arrive at the points, the whole of it must rise, and the last
  -- step must land on full scale.
  procedure check_curve(constant curve: byte_string;
                        constant name: string) is
    variable word: unsigned(8*curve_bytes_c-1 downto 0);
    variable value, delta, walked: integer;
    variable base: natural;
  begin
    walked := 0;

    for i in 0 to 2 ** table_l2_c - 1
    loop
      base := curve'low + i * curve_bytes_c;
      word := from_le(curve(base to base + curve_bytes_c - 1));
      value := to_integer(word(curve_values_c-1 downto 0));
      delta := to_integer(word(curve_values_c+curve_deltas_c-1
                               downto curve_values_c));

      assert value = walked
        report name & ": point " & to_string(i) & " is " & to_string(value)
        & " where its steps arrived at " & to_string(walked)
        severity failure;
      assert value < 2 ** curve_values_c
        report name & ": point " & to_string(i) & " is past full scale"
        severity failure;

      walked := value + delta;
    end loop;

    assert walked = 2 ** curve_values_c - 1
      report name & ": the last step landed on " & to_string(walked)
      & " rather than on full scale"
      severity failure;
  end procedure;

  procedure stream_put(signal m: out nsl_amba.axi4_stream.master_t;
                       signal s: in nsl_amba.axi4_stream.slave_t;
                       constant cfg: config_t;
                       constant f: frame_t) is
  begin
    wait until falling_edge(clock_s);
    m <= transfer(cfg, f, last => true);

    loop
      wait until rising_edge(clock_s);
      exit when is_ready(cfg, s);
    end loop;

    wait until falling_edge(clock_s);
    m <= transfer_defaults(cfg);
  end procedure;

  procedure stream_get(signal m: in nsl_amba.axi4_stream.master_t;
                       signal s: out nsl_amba.axi4_stream.slave_t;
                       constant cfg: config_t;
                       variable f: out frame_t) is
  begin
    wait until falling_edge(clock_s);
    s <= accept(cfg, true);

    loop
      wait until rising_edge(clock_s);
      exit when is_valid(cfg, m);
    end loop;

    f := frame(cfg, m);

    wait until falling_edge(clock_s);
    s <= accept(cfg, false);
  end procedure;

begin

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 10 ns,
      reset_duration(0) => 30 ns,
      reset_n_o(0) => reset_n_s,
      clock_o(0) => clock_s,
      done_i => done_s
      );

  -- An amplifier with somewhere to put its gain
  amp: nsl_audio.effect.pcm_gain
    generic map(
      in_config_c => narrow_c,
      out_config_c => wide_c
      )
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,

      in_i => amp_in_m_s,
      in_o => amp_in_s_s,

      out_o => amp_out_m_s,
      out_i => amp_out_s_s,

      gain_i => gain_s
      );

  -- One with none, so that a gain it cannot hold shows
  rail: nsl_audio.effect.pcm_gain
    generic map(
      in_config_c => narrow_c,
      out_config_c => narrow_c
      )
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,

      in_i => rail_in_m_s,
      in_o => rail_in_s_s,

      out_o => rail_out_m_s,
      out_i => rail_out_s_s,

      gain_i => gain_s
      );

  saturator: nsl_audio.effect.pcm_shaper
    generic map(
      in_config_c => wide_c,
      out_config_c => narrow_c,
      shape_c => SHAPE_TANH,
      domain_l2_c => 2,
      table_l2_c => 8
      )
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,

      in_i => shaper_in_m_s,
      in_o => shaper_in_s_s,

      out_o => shaper_out_m_s,
      out_i => shaper_out_s_s
      );

  tone: nsl_audio.effect.pcm_tone
    generic map(
      in_config_c => narrow_c,
      out_config_c => narrow_c,
      rate_c => rate_c,
      lowpass_hz_c => 700.0,
      highpass_hz_c => 1500.0,
      guard_bits_c => 8
      )
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,

      in_i => tone_in_m_s,
      in_o => tone_in_s_s,

      out_o => tone_out_m_s,
      out_i => tone_out_s_s,

      blend_i => blend_s
      );

  main: process is
    variable got: frame_t;
    variable left, right, last_level, level: integer;

    -- One frame in, one frame out, of the amplifier with headroom
    procedure amplify(constant a, b: integer;
                      variable ra, rb: out integer) is
      variable f: frame_t;
    begin
      stream_put(amp_in_m_s, amp_in_s_s, narrow_c,
                 frame_of(a, b, sample_bits_c));
      stream_get(amp_out_m_s, amp_out_s_s, wide_c, f);
      ra := number_of(f, 0, wide_bits_c);
      rb := number_of(f, 1, wide_bits_c);
    end procedure;

    -- What the saturator makes of one number, on both channels at
    -- once so that the two are shown to stay apart
    procedure saturate(constant a, b: integer;
                       variable ra, rb: out integer) is
      variable f: frame_t;
    begin
      stream_put(shaper_in_m_s, shaper_in_s_s, wide_c,
                 frame_of(a, b, wide_bits_c));
      stream_get(shaper_out_m_s, shaper_out_s_s, narrow_c, f);
      ra := number_of(f, 0, sample_bits_c);
      rb := number_of(f, 1, sample_bits_c);
    end procedure;

    -- One frame through the tone control
    procedure filter(constant a: integer;
                     variable ra: out integer) is
      variable f: frame_t;
      variable one, other: integer;
    begin
      stream_put(tone_in_m_s, tone_in_s_s, narrow_c,
                 frame_of(a, -a, sample_bits_c));
      stream_get(tone_out_m_s, tone_out_s_s, narrow_c, f);
      one := number_of(f, 0, sample_bits_c);
      other := number_of(f, 1, sample_bits_c);

      -- The two channels are fed the same thing with opposite signs
      -- and must come back the same way.  Not to the bit: the filter
      -- keeps more of a sample than it hands back and drops the rest,
      -- and dropping bits is a fall towards minus infinity rather
      -- than towards zero, so one side lands a few steps lower than
      -- the other.  There are three such falls between a sample
      -- arriving and one leaving, and a filter that has settled sits
      -- wherever its own steps became too small to take.
      assert abs(other + one) <= 4
        report "Tone control gave the two channels different answers: "
        & to_string(one) & " and " & to_string(other)
        severity failure;

      ra := one;
    end procedure;

    -- Many of the same frame, which is what a filter needs to settle
    procedure filter_steady(constant a: integer;
                            constant count: natural;
                            variable ra: out integer) is
    begin
      for i in 1 to count
      loop
        filter(a, ra);
      end loop;
    end procedure;

  begin
    amp_in_m_s <= transfer_defaults(narrow_c);
    rail_in_m_s <= transfer_defaults(narrow_c);
    shaper_in_m_s <= transfer_defaults(wide_c);
    tone_in_m_s <= transfer_defaults(narrow_c);
    amp_out_s_s <= accept(wide_c, false);
    rail_out_s_s <= accept(narrow_c, false);
    shaper_out_s_s <= accept(narrow_c, false);
    tone_out_s_s <= accept(narrow_c, false);
    gain_s <= to_ufixed(1.0, gain_s'left, gain_s'right);
    blend_s <= to_ufixed(0.0, blend_s'left, blend_s'right);
    done_s <= "0";

    wait until reset_n_s = '1';
    wait until falling_edge(clock_s);

    check_curve(tanh_curve_c, "Hyperbolic tangent");
    check_curve(knee_curve_c, "Soft knee");
    check_curve(diode_curve_c, "Diode");

    -- Unity gain moves nothing, and the two channels stay apart.
    amplify(1234, -5678, left, right);
    assert left = 1234 and right = -5678
      report "Unity gain gave " & to_string(left) & " and " & to_string(right)
      severity failure;

    -- A gain of sixteen is sixteen times, exactly: a sample is an
    -- integer and the wider stream states the same least significant
    -- bit, so nothing is rounded here.
    gain_s <= to_ufixed(16.0, gain_s'left, gain_s'right);
    amplify(1234, -5678, left, right);
    assert left = 1234 * 16 and right = -5678 * 16
      report "Gain of sixteen gave " & to_string(left) & " and "
      & to_string(right)
      severity failure;

    -- A gain with a fraction rounds down, both ways, which is what
    -- dropping the bits under the point does.
    gain_s <= to_ufixed(2.5, gain_s'left, gain_s'right);
    amplify(3, -3, left, right);
    assert left = 7 and right = -8
      report "Gain of two and a half gave " & to_string(left) & " and "
      & to_string(right)
      severity failure;

    -- Asked for more than the stream can hold, an amplifier stops at
    -- the rail rather than wrapping round it.
    gain_s <= to_ufixed(16.0, gain_s'left, gain_s'right);
    stream_put(rail_in_m_s, rail_in_s_s, narrow_c,
               frame_of(2 ** 21, -(2 ** 21), sample_bits_c));
    stream_get(rail_out_m_s, rail_out_s_s, narrow_c, got);
    assert number_of(got, 0, sample_bits_c) = full_scale_c
      and number_of(got, 1, sample_bits_c) = -full_scale_c - 1
      report "Gain past the rail gave "
      & to_string(number_of(got, 0, sample_bits_c)) & " and "
      & to_string(number_of(got, 1, sample_bits_c))
      severity failure;

    -- Nothing in, nothing out.
    saturate(0, 0, left, right);
    assert left = 0 and right = 0
      report "Saturator turned silence into " & to_string(left) & " and "
      & to_string(right)
      severity failure;

    -- A quiet signal comes out where it went in: the curve has unity
    -- slope near nothing, and a sample keeps the same least
    -- significant bit whatever the width of the stream holding it.
    -- What separates the two is the table being a chord of the curve
    -- rather than the curve, which is worth a handful of bits of full
    -- scale wherever one looks.
    saturate(10000, -10000, left, right);
    assert abs(left - 10000) < 32 and left = -right
      report "A quiet signal came out of the saturator as "
      & to_string(left) & " and " & to_string(right)
      severity failure;

    -- Driven past the top of the table there is nothing left to give.
    saturate(8 * 2 ** (sample_bits_c-1), -8 * 2 ** (sample_bits_c-1),
             left, right);
    assert left = full_scale_c and right = -full_scale_c
      report "Driven hard, the saturator gave " & to_string(left)
      & " and " & to_string(right)
      severity failure;

    -- And it rises all the way there, never stepping back.
    last_level := -1;
    for i in 0 to 64
    loop
      saturate(i * 2 ** (sample_bits_c-1) / 16, 0, level, right);

      assert level >= last_level
        report "Saturator fell back at step " & to_string(i) & ": "
        & to_string(level) & " after " & to_string(last_level)
        severity failure;
      assert level <= full_scale_c
        report "Saturator went past full scale at step " & to_string(i)
        severity failure;
      assert right = 0
        report "Saturator turned silence into " & to_string(right)
        severity failure;

      last_level := level;
    end loop;

    -- At the bottom of its travel the tone control is the lowpass,
    -- and a lowpass eventually agrees with a steady signal.
    blend_s <= to_ufixed(0.0, blend_s'left, blend_s'right);
    filter_steady(100000, 2000, level);
    assert abs(level - 100000) < 64
      report "Lowpass settled at " & to_string(level) & " rather than 100000"
      severity failure;

    -- At the top of its travel it is the highpass, which has nothing
    -- to say about a signal that is not moving.
    blend_s <= to_ufixed(1.0, blend_s'left, blend_s'right);
    filter_steady(100000, 2000, level);
    assert abs(level) < 64
      report "Highpass settled at " & to_string(level) & " rather than nothing"
      severity failure;

    -- The other way round, on something moving as fast as a stream
    -- can carry: the highpass passes it and the lowpass does not.
    for i in 1 to 2000
    loop
      filter(100000, level);
      filter(-100000, level);
    end loop;
    -- Most of it, not all: a one-pole highpass is one minus a
    -- lowpass, and a lowpass fed something alternating settles at a
    -- small alternating value of its own rather than at nothing.
    assert level < -70000 and level >= -100000
      report "Highpass gave " & to_string(level)
      & " for a signal at half the frame rate"
      severity failure;

    blend_s <= to_ufixed(0.0, blend_s'left, blend_s'right);
    for i in 1 to 2000
    loop
      filter(100000, level);
      filter(-100000, level);
    end loop;
    assert abs(level) < 10000
      report "Lowpass gave " & to_string(level)
      & " for a signal at half the frame rate"
      severity failure;

    wait until falling_edge(clock_s);
    done_s <= "1";
    wait;
  end process;

end architecture;
