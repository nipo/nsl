library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_audio, nsl_math, nsl_synthesis;
use nsl_audio.pcm.all;
use nsl_audio.pcm_stream.all;
use nsl_math.fixed.all;

entity pcm_echo is
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
end entity;

architecture beh of pcm_echo is

  constant sample_bits_c : natural := in_config_c.sample_bits;
  constant channels_c : natural := in_config_c.channel_count;
  constant delay_depth_c : natural := 2 ** max_delay_l2_c;

  -- One extra integer bit accommodates the unity dry-plus-wet and
  -- input-plus-feedback sums.  Fractional guard bits keep gain products
  -- from being quantized before those sums.
  subtype value_t is sfixed(sample_bits_c+1 downto -guard_bits_c);
  subtype sample_word_t is signed(sample_bits_c-1 downto 0);
  type delay_frame_t is array (natural range 0 to channels_c-1)
    of sample_word_t;
  type delay_memory_t is array (natural range 0 to delay_depth_c-1)
    of delay_frame_t;

  constant value_zero_c : value_t := (others => '0');
  constant delay_frame_zero_c : delay_frame_t := (others => (others => '0'));

  type state_t is (
    ST_CLEAR,
    ST_TAKE,
    ST_MIX,
    ST_WRITE,
    ST_PUT
    );

  type regs_t is
  record
    state : state_t;
    taken : nsl_amba.axi4_stream.master_t;
    made : frame_t;
    feedback_frame : delay_frame_t;
    delayed_frame : delay_frame_t;
    channel : natural range 0 to max_channel_count_c-1;
    write_address : natural range 0 to delay_depth_c-1;
    clear_address : natural range 0 to delay_depth_c-1;
    delay : unsigned(max_delay_l2_c-1 downto 0);
  end record;

  signal r, rin : regs_t;
  signal delay_memory : delay_memory_t;

  function delay_address(write_address : natural;
                         delay : unsigned) return natural
  is
    variable delay_n : natural;
  begin
    delay_n := to_integer(delay);
    if delay_n > write_address then
      return write_address + delay_depth_c - delay_n;
    end if;
    return write_address - delay_n;
  end function;

begin

  shape_check: nsl_synthesis.assertion.synth_assert
    generic map(
      message_c => "An echo keeps the PCM frame shape, signed sample coding, "
      & "AXI sideband widths and packet markers unchanged",
      condition_c => max_delay_l2_c > 0
      and max_delay_l2_c < 31
      and compatible(in_config_c, out_config_c)
      and in_config_c.coding = CODING_SIGNED
      and out_config_c.coding = CODING_SIGNED
      )
    port map(
      unused_i => '0'
      );

  regs: process(clock_i, reset_n_i) is
    variable read_address : natural range 0 to delay_depth_c-1;
  begin
    if rising_edge(clock_i) then
      r <= rin;

      -- The RAM is cleared a word per clock.  This is intentionally a
      -- post-reset operation: it gives deterministic contents while still
      -- allowing a block RAM implementation to be selected by synthesis.
      if r.state = ST_CLEAR then
        delay_memory(r.clear_address) <= delay_frame_zero_c;
      elsif r.state = ST_WRITE then
        delay_memory(r.write_address) <= r.feedback_frame;
      elsif r.state = ST_TAKE
        and is_valid(in_config_c, in_i)
        and delay_i = r.delay then
        if r.delay = 0 then
          r.delayed_frame <= delay_frame_zero_c;
        else
          read_address := delay_address(r.write_address, r.delay);
          r.delayed_frame <= delay_memory(read_address);
        end if;
      end if;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_CLEAR;
      r.taken <= transfer_defaults(in_config_c);
      r.made <= frame_zero_c;
      r.feedback_frame <= delay_frame_zero_c;
      r.delayed_frame <= delay_frame_zero_c;
      r.channel <= 0;
      r.write_address <= 0;
      r.clear_address <= 0;
      r.delay <= (others => '0');
    end if;
  end process;

  transition: process(r, in_i, out_i, delay_i, dry_i, wet_i, feedback_i) is
    variable taken_frame : frame_t;
    variable sample : value_t;
    variable delayed : value_t;
    variable dry_value : value_t;
    variable wet_value : value_t;
    variable feedback_value : value_t;
    variable mix_sum : sfixed(value_t'left+1 downto value_t'right);
    variable feedback_sum : sfixed(value_t'left+1 downto value_t'right);
  begin
    rin <= r;

    taken_frame := frame(in_config_c, r.taken);

    sample := resize(
      to_sfixed(signed(taken_frame(r.channel).sample(sample_bits_c-1 downto 0))),
      value_t'left, value_t'right);

    if r.delay = 0 then
      delayed := value_zero_c;
    else
      delayed := resize(to_sfixed(r.delayed_frame(r.channel)),
                        value_t'left, value_t'right);
    end if;

    dry_value := mul(sample, dry_i, value_t'left, value_t'right);
    wet_value := mul(delayed, wet_i, value_t'left, value_t'right);
    feedback_value := mul(delayed, feedback_i,
                          value_t'left, value_t'right);
    mix_sum := add_extend(dry_value, wet_value);
    feedback_sum := add_extend(sample, feedback_value);

    -- A delay change is a discontinuity in the feedback state.  Do not
    -- accept or emit a beat in the cycle in which that discontinuity is
    -- observed.
    if r.state /= ST_CLEAR and delay_i /= r.delay then
      rin.state <= ST_CLEAR;
      rin.clear_address <= 0;
      rin.write_address <= 0;
    else
      case r.state is
        when ST_CLEAR =>
          if r.clear_address = delay_depth_c-1 then
            rin.state <= ST_TAKE;
            rin.clear_address <= 0;
            rin.write_address <= 0;
            rin.delay <= delay_i;
          else
            rin.clear_address <= r.clear_address + 1;
          end if;

        when ST_TAKE =>
          if is_valid(in_config_c, in_i) then
            rin.taken <= in_i;
            rin.channel <= 0;
            rin.state <= ST_MIX;
          end if;

        when ST_MIX =>
          rin.made(r.channel).sample <= to_sample(
            unsigned(to_signed(resize_saturate(mix_sum,
                                                sample_bits_c-1, 0))),
            CODING_SIGNED);
          rin.made(r.channel).sideband <= taken_frame(r.channel).sideband;
          rin.feedback_frame(r.channel) <=
            to_signed(resize_saturate(feedback_sum,
                                      sample_bits_c-1, 0));

          if r.channel = channels_c-1 then
            rin.state <= ST_WRITE;
          else
            rin.channel <= r.channel + 1;
          end if;

        when ST_WRITE =>
          if r.write_address = delay_depth_c-1 then
            rin.write_address <= 0;
          else
            rin.write_address <= r.write_address + 1;
          end if;
          rin.state <= ST_PUT;

        when ST_PUT =>
          if is_ready(out_config_c, out_i) then
            rin.state <= ST_TAKE;
          end if;
      end case;
    end if;
  end process;

  in_o <= accept(in_config_c, r.state = ST_TAKE and delay_i = r.delay);

  moore: process(r, delay_i) is
    variable output_m : nsl_amba.axi4_stream.master_t;
  begin
    output_m := transfer(
      cfg => out_config_c,
      frame => r.made,
       valid => r.state = ST_PUT and delay_i = r.delay,
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
