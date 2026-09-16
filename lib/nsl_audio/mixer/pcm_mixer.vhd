library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_audio, nsl_math, nsl_synthesis;
use nsl_audio.pcm.all;
use nsl_audio.pcm_stream.all;
use nsl_math.fixed.all;

entity pcm_mixer is
  generic(
    in_a_config_c : nsl_audio.pcm_stream.config_t;
    in_b_config_c : nsl_audio.pcm_stream.config_t;
    out_config_c : nsl_audio.pcm_stream.config_t;
    guard_bits_c : natural := 4
    );
  port(
    reset_n_i : in std_ulogic;
    clock_i : in std_ulogic;

    in_a_i : in nsl_amba.axi4_stream.master_t;
    in_a_o : out nsl_amba.axi4_stream.slave_t;

    in_b_i : in nsl_amba.axi4_stream.master_t;
    in_b_o : out nsl_amba.axi4_stream.slave_t;

    out_o : out nsl_amba.axi4_stream.master_t;
    out_i : in nsl_amba.axi4_stream.slave_t;

    gain_a_i : in nsl_math.fixed.ufixed;
    gain_b_i : in nsl_math.fixed.ufixed
    );
end entity;

architecture beh of pcm_mixer is

  constant sample_bits_c : natural := in_a_config_c.sample_bits;
  constant channels_c : natural := in_a_config_c.channel_count;

  subtype value_t is sfixed(sample_bits_c downto -guard_bits_c);
  type state_t is (ST_TAKE, ST_MIX, ST_PUT);

  type regs_t is
  record
    state : state_t;
    taken_a : nsl_amba.axi4_stream.master_t;
    taken_b : nsl_amba.axi4_stream.master_t;
    made : frame_t;
    channel : natural range 0 to max_channel_count_c-1;
  end record;

  signal r, rin : regs_t;

begin

  shape_check: nsl_synthesis.assertion.synth_assert
    generic map(
      message_c => "A mixer takes two compatible signed PCM streams and "
      & "keeps the output stream compatible with them",
      condition_c => compatible(in_a_config_c, in_b_config_c)
      and compatible(in_a_config_c, out_config_c)
      and in_a_config_c.coding = CODING_SIGNED
      and in_b_config_c.coding = CODING_SIGNED
      and out_config_c.coding = CODING_SIGNED
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
      r.taken_a <= transfer_defaults(in_a_config_c);
      r.taken_b <= transfer_defaults(in_b_config_c);
      r.made <= frame_zero_c;
      r.channel <= 0;
    end if;
  end process;

  transition: process(r, in_a_i, in_b_i, out_i, gain_a_i, gain_b_i) is
    variable frame_a : frame_t;
    variable frame_b : frame_t;
    variable sample_a : value_t;
    variable sample_b : value_t;
    variable scaled_a : value_t;
    variable scaled_b : value_t;
    variable mixed : sfixed(value_t'left+1 downto value_t'right);
  begin
    rin <= r;

    frame_a := frame(in_a_config_c, r.taken_a);
    frame_b := frame(in_b_config_c, r.taken_b);
    sample_a := resize(
      to_sfixed(signed(frame_a(r.channel).sample(sample_bits_c-1 downto 0))),
      value_t'left, value_t'right);
    sample_b := resize(
      to_sfixed(signed(frame_b(r.channel).sample(sample_bits_c-1 downto 0))),
      value_t'left, value_t'right);
    scaled_a := mul(sample_a, gain_a_i, value_t'left, value_t'right);
    scaled_b := mul(sample_b, gain_b_i, value_t'left, value_t'right);
    mixed := add_extend(scaled_a, scaled_b);

    case r.state is
      when ST_TAKE =>
        if is_valid(in_a_config_c, in_a_i)
          and is_valid(in_b_config_c, in_b_i) then
          rin.taken_a <= in_a_i;
          rin.taken_b <= in_b_i;
          rin.channel <= 0;
          rin.state <= ST_MIX;
        end if;

      when ST_MIX =>
        rin.made(r.channel).sample <= to_sample(
          unsigned(to_signed(resize_saturate(mixed, sample_bits_c-1, 0))),
          CODING_SIGNED);
        rin.made(r.channel).sideband <= frame_a(r.channel).sideband;

        if r.channel = channels_c-1 then
          rin.state <= ST_PUT;
        else
          rin.channel <= r.channel + 1;
        end if;

      when ST_PUT =>
        if is_ready(out_config_c, out_i) then
          rin.state <= ST_TAKE;
        end if;
    end case;
  end process;

  in_a_o <= accept(in_a_config_c,
                   r.state = ST_TAKE and is_valid(in_b_config_c, in_b_i));
  in_b_o <= accept(in_b_config_c,
                   r.state = ST_TAKE and is_valid(in_a_config_c, in_a_i));

  moore: process(r) is
    variable output_m : nsl_amba.axi4_stream.master_t;
  begin
    output_m := transfer(
      cfg => out_config_c,
      frame => r.made,
      valid => r.state = ST_PUT,
      last => is_last(in_a_config_c, r.taken_a),
      block_start => is_block(in_a_config_c, r.taken_a),
      error => is_error(in_a_config_c, r.taken_a));
    output_m.id := r.taken_a.id;
    output_m.dest := r.taken_a.dest;
    output_m.keep := r.taken_a.keep;
    output_m.strobe := r.taken_a.strobe;
    out_o <= output_m;
  end process;

end architecture;
