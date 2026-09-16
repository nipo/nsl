library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_audio, nsl_math, nsl_synthesis;
use nsl_audio.pcm.all;
use nsl_audio.pcm_stream.all;
use nsl_math.fixed.all;

entity pcm_octaver is
  generic(
    in_config_c : nsl_audio.pcm_stream.config_t;
    out_config_c : nsl_audio.pcm_stream.config_t
    );
  port(
    reset_n_i : in std_ulogic;
    clock_i : in std_ulogic;

    in_i : in nsl_amba.axi4_stream.master_t;
    in_o : out nsl_amba.axi4_stream.slave_t;

    out_o : out nsl_amba.axi4_stream.master_t;
    out_i : in nsl_amba.axi4_stream.slave_t
    );
end entity;

architecture beh of pcm_octaver is

  constant sample_bits_c : natural := in_config_c.sample_bits;
  constant out_bits_c : natural := out_config_c.sample_bits;
  constant channels_c : natural := in_config_c.channel_count;

  subtype sample_value_t is sfixed(sample_bits_c-1 downto 0);
  subtype value_t is sfixed(sample_bits_c downto 0);
  type phase_vector_t is array (natural range 0 to max_channel_count_c-1)
    of std_ulogic;

  type state_t is (
    ST_TAKE,
    ST_PROCESS,
    ST_PUT
    );

  type regs_t is
  record
    state : state_t;
    taken : nsl_amba.axi4_stream.master_t;
    made : frame_t;
    channel : natural range 0 to max_channel_count_c-1;
    phase : phase_vector_t;
    previous_negative : phase_vector_t;
  end record;

  signal r, rin : regs_t;

  function effected_sample(value : sample_value_t;
                           phase : std_ulogic) return sample_t
  is
    variable sample, carrier : value_t;
  begin
    sample := resize(value, value_t'left, value_t'right);
    carrier := sample;
    if phase = '1' then
      -- The extra value bit keeps the minimum negative sample representable
      -- while the oscillator changes its polarity.
      carrier := -carrier;
    end if;

    return to_sample(
      unsigned(to_signed(resize_saturate(carrier, out_bits_c-1, 0))),
      CODING_SIGNED);
  end function;

begin

  shape_check: nsl_synthesis.assertion.synth_assert
    generic map(
      message_c => "An octaver keeps the signed PCM frame shape, AXI sidebands "
       & "and packet markers unchanged",
      condition_c => compatible(in_config_c, out_config_c)
      and in_config_c.coding = CODING_SIGNED
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
      r.taken <= transfer_defaults(in_config_c);
      r.made <= frame_zero_c;
      r.channel <= 0;
      r.phase <= (others => '0');
      r.previous_negative <= (others => '0');
    end if;
  end process;

  transition: process(r, in_i, out_i) is
    variable taken_frame : frame_t;
    variable sample : sample_value_t;
    variable phase : std_ulogic;
  begin
    rin <= r;

    taken_frame := frame(in_config_c, r.taken);
    sample := to_sfixed(
      signed(taken_frame(r.channel).sample(sample_bits_c-1 downto 0)));

    case r.state is
      when ST_TAKE =>
        if is_valid(in_config_c, in_i) then
          rin.taken <= in_i;
          rin.channel <= 0;

          rin.state <= ST_PROCESS;
        end if;

      when ST_PROCESS =>
        phase := r.phase(r.channel);
        if r.previous_negative(r.channel) = '1'
          and sample(sample'left) = '0' then
          phase := not phase;
        end if;

        rin.made(r.channel).sample <= effected_sample(sample, phase);
        rin.made(r.channel).sideband <= taken_frame(r.channel).sideband;

        -- One rising zero crossing advances the divide-by-two oscillator.
        rin.phase(r.channel) <= phase;
        rin.previous_negative(r.channel) <= sample(sample'left);

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

  moore: process(r) is
    variable output_m : nsl_amba.axi4_stream.master_t;
  begin
    in_o <= accept(in_config_c, r.state = ST_TAKE);

    output_m := transfer(out_config_c, r.made,
                         valid => r.state = ST_PUT,
                         last => is_last(in_config_c, r.taken),
                         block_start => is_block(in_config_c, r.taken),
                         error => is_error(in_config_c, r.taken));
    output_m.id := r.taken.id;
    output_m.dest := r.taken.dest;
    output_m.keep := r.taken.keep;
    output_m.strobe := r.taken.strobe;

    out_o <= output_m;
  end process;

end architecture;
