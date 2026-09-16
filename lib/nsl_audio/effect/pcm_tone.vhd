library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_audio, nsl_logic, nsl_math, nsl_synthesis, work;
use nsl_logic.bool.all;
use nsl_audio.pcm.all;
use nsl_audio.pcm_stream.all;
use nsl_math.fixed.all;
use work.effect.all;

entity pcm_tone is
  generic(
    in_config_c : nsl_audio.pcm_stream.config_t;
    out_config_c : nsl_audio.pcm_stream.config_t;
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
end entity;

architecture beh of pcm_tone is

  constant sample_bits_c: natural := in_config_c.sample_bits;
  constant channels_c: natural := in_config_c.channel_count;
  constant coefficient_bits_c: natural := 20;

  -- A sample as a number, with room under it for the filter to keep
  -- what a sample cannot say, and one bit over it so a difference of
  -- two samples still fits.
  subtype value_t is sfixed(sample_bits_c downto -guard_bits_c);
  type value_vector is array (natural range 0 to max_channel_count_c-1)
    of value_t;

  constant value_zero_c: value_t := (others => '0');

  constant lowpass_a_c: real := one_pole_coefficient(lowpass_hz_c, real(rate_c));
  constant highpass_a_c: real := one_pole_coefficient(highpass_hz_c, real(rate_c));

  constant lowpass_coefficient_c: ufixed(-1 downto -coefficient_bits_c)
    := to_ufixed(lowpass_a_c, -1, -coefficient_bits_c);
  constant highpass_coefficient_c: ufixed(-1 downto -coefficient_bits_c)
    := to_ufixed(highpass_a_c, -1, -coefficient_bits_c);

  type state_t is (
    ST_TAKE,
    ST_ERROR,
    ST_PRODUCT,
    ST_UPDATE,
    ST_PATHS,
    ST_DIFFERENCE,
    ST_BLEND,
    ST_MIX,
    ST_PUT
    );

  type regs_t is
  record
    state: state_t;
    taken: frame_t;
    made: frame_t;
    channel: natural range 0 to max_channel_count_c-1;
    last, block_start, error: std_ulogic;

    -- What the two filters have settled at, one pair per channel
    low: value_vector;
    high: value_vector;

    sample: value_t;
    low_error, high_error: value_t;
    low_step, high_step: value_t;
    lowpass, highpass: value_t;
    difference, blended: value_t;
  end record;

  signal r, rin: regs_t;

begin

  shape_check: nsl_synthesis.assertion.synth_assert
    generic map(
      message_c => "A tone control carries the channels, sample width and "
      & "sideband it was given, works on signed samples, and needs enough "
      & "guard bits for its lowest corner to move the filter at all",
      condition_c => in_config_c.channel_count = out_config_c.channel_count
      and in_config_c.sample_bits = out_config_c.sample_bits
      and in_config_c.sideband_bits = out_config_c.sideband_bits
      and in_config_c.coding = CODING_SIGNED
      and out_config_c.coding = CODING_SIGNED
      and lowpass_a_c >= 2.0 ** (-guard_bits_c)
      and highpass_a_c >= 2.0 ** (-guard_bits_c)
      and lowpass_a_c < 1.0
      and highpass_a_c < 1.0
      )
    port map(
      unused_i => '0'
      );

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_TAKE;
      r.taken <= frame_zero_c;
      r.made <= frame_zero_c;
      r.channel <= 0;
      r.last <= '0';
      r.block_start <= '0';
      r.error <= '0';
      r.low <= (others => value_zero_c);
      r.high <= (others => value_zero_c);
      r.sample <= value_zero_c;
      r.low_error <= value_zero_c;
      r.high_error <= value_zero_c;
      r.low_step <= value_zero_c;
      r.high_step <= value_zero_c;
      r.lowpass <= value_zero_c;
      r.highpass <= value_zero_c;
      r.difference <= value_zero_c;
      r.blended <= value_zero_c;
    end if;
  end process;

  transition: process(r, in_i, out_i, blend_i) is
    variable sample: value_t;
  begin
    rin <= r;

    sample := resize(to_sfixed(signed(r.taken(r.channel).sample(sample_bits_c-1 downto 0))),
                     value_t'left, value_t'right);

    case r.state is
      when ST_TAKE =>
        if is_valid(in_config_c, in_i) then
          rin.taken <= frame(in_config_c, in_i);
          rin.last <= to_logic(is_last(in_config_c, in_i));
          rin.block_start <= to_logic(is_block(in_config_c, in_i));
          rin.error <= to_logic(is_error(in_config_c, in_i));
          rin.channel <= 0;
          rin.state <= ST_ERROR;
        end if;

      when ST_ERROR =>
        rin.sample <= sample;
        rin.low_error <= resize_saturate(sub_extend(sample, r.low(r.channel)),
                                         value_t'left, value_t'right);
        rin.high_error <= resize_saturate(sub_extend(sample, r.high(r.channel)),
                                          value_t'left, value_t'right);
        rin.state <= ST_PRODUCT;

      when ST_PRODUCT =>
        rin.low_step <= mul(r.low_error, lowpass_coefficient_c,
                            value_t'left, value_t'right);
        rin.high_step <= mul(r.high_error, highpass_coefficient_c,
                             value_t'left, value_t'right);
        rin.state <= ST_UPDATE;

      when ST_UPDATE =>
        rin.low(r.channel) <= add_saturate(r.low(r.channel), r.low_step);
        rin.high(r.channel) <= add_saturate(r.high(r.channel), r.high_step);
        rin.state <= ST_PATHS;

      when ST_PATHS =>
        rin.lowpass <= r.low(r.channel);
        rin.highpass <= resize_saturate(sub_extend(r.sample, r.high(r.channel)),
                                        value_t'left, value_t'right);
        rin.state <= ST_DIFFERENCE;

      when ST_DIFFERENCE =>
        rin.difference <= resize_saturate(sub_extend(r.highpass, r.lowpass),
                                          value_t'left, value_t'right);
        rin.state <= ST_BLEND;

      when ST_BLEND =>
        rin.blended <= mul(r.difference, blend_i,
                           value_t'left, value_t'right);
        rin.state <= ST_MIX;

      when ST_MIX =>
        rin.made(r.channel).sideband <= r.taken(r.channel).sideband;
        rin.made(r.channel).sample
          <= to_sample(unsigned(to_signed(resize_saturate(
            add_saturate(r.lowpass, r.blended), sample_bits_c-1, 0))),
                       CODING_SIGNED);

        if r.channel = channels_c-1 then
          rin.state <= ST_PUT;
        else
          rin.channel <= r.channel + 1;
          rin.state <= ST_ERROR;
        end if;

      when ST_PUT =>
        if is_ready(out_config_c, out_i) then
          rin.state <= ST_TAKE;
        end if;
    end case;
  end process;

  moore: process(r) is
  begin
    in_o <= accept(in_config_c, r.state = ST_TAKE);
    out_o <= transfer(out_config_c, r.made,
                      valid => r.state = ST_PUT,
                      last => r.last = '1',
                      block_start => r.block_start = '1',
                      error => r.error = '1');
  end process;

end architecture;
