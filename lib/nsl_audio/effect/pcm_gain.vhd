library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_audio, nsl_logic, nsl_math, nsl_synthesis, work;
use nsl_logic.bool.all;
use nsl_audio.pcm.all;
use nsl_audio.pcm_stream.all;
use nsl_math.fixed.all;

entity pcm_gain is
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
    out_i : in nsl_amba.axi4_stream.slave_t;

    gain_i : in nsl_math.fixed.ufixed
    );
end entity;

architecture beh of pcm_gain is

  constant in_bits_c: natural := in_config_c.sample_bits;
  constant out_bits_c: natural := out_config_c.sample_bits;
  constant channels_c: natural := in_config_c.channel_count;

  type state_t is (
    ST_TAKE,
    ST_SCALE,
    ST_PUT
    );

  type regs_t is
  record
    state: state_t;
    taken: frame_t;
    made: frame_t;
    channel: natural range 0 to max_channel_count_c-1;
    last, block_start, error: std_ulogic;
  end record;

  signal r, rin: regs_t;

begin

  shape: nsl_synthesis.assertion.synth_assert
    generic map(
      message_c => "An amplifier carries the channels and sideband it was "
      & "given, and works on signed samples",
      condition_c => in_config_c.channel_count = out_config_c.channel_count
      and in_config_c.sideband_bits = out_config_c.sideband_bits
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
      r.taken <= frame_zero_c;
      r.made <= frame_zero_c;
      r.channel <= 0;
      r.last <= '0';
      r.block_start <= '0';
      r.error <= '0';
    end if;
  end process;

  transition: process(r, in_i, out_i, gain_i) is
    variable sample: sfixed(in_bits_c-1 downto 0);
    variable scaled: sfixed(out_bits_c-1 downto 0);
  begin
    rin <= r;

    sample := to_sfixed(signed(r.taken(r.channel).sample(in_bits_c-1 downto 0)));
    scaled := mul(sample, gain_i, scaled'left, scaled'right);

    case r.state is
      when ST_TAKE =>
        if is_valid(in_config_c, in_i) then
          rin.taken <= frame(in_config_c, in_i);
          rin.last <= to_logic(is_last(in_config_c, in_i));
          rin.block_start <= to_logic(is_block(in_config_c, in_i));
          rin.error <= to_logic(is_error(in_config_c, in_i));
          rin.channel <= 0;
          rin.state <= ST_SCALE;
        end if;

      when ST_SCALE =>
        rin.made(r.channel).sample
          <= to_sample(unsigned(to_signed(scaled)), CODING_SIGNED);
        rin.made(r.channel).sideband <= r.taken(r.channel).sideband;

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
  begin
    in_o <= accept(in_config_c, r.state = ST_TAKE);
    out_o <= transfer(out_config_c, r.made,
                      valid => r.state = ST_PUT,
                      last => r.last = '1',
                      block_start => r.block_start = '1',
                      error => r.error = '1');
  end process;

end architecture;
