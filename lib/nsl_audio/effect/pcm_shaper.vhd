library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_audio, nsl_logic, nsl_memory, nsl_synthesis, work;
use nsl_logic.bool.all;
use nsl_audio.pcm.all;
use nsl_audio.pcm_stream.all;
use work.effect.all;

entity pcm_shaper is
  generic(
    in_config_c : nsl_audio.pcm_stream.config_t;
    out_config_c : nsl_audio.pcm_stream.config_t;
    shape_c : shape_t := SHAPE_TANH;
    knee_c : real := 0.5;
    domain_l2_c : natural := 2;
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
end entity;

architecture beh of pcm_shaper is

  constant in_bits_c: natural := in_config_c.sample_bits;
  constant out_bits_c: natural := out_config_c.sample_bits;
  constant channels_c: natural := in_config_c.channel_count;

  -- A magnitude the table has something to say about: full scale of
  -- the outgoing stream, domain_l2_c times over.
  constant magnitude_bits_c: natural := out_bits_c - 1 + domain_l2_c;
  -- What is left of a magnitude once the table point has been taken
  -- out of it, which is how far between two points it fell.
  constant frac_bits_c: natural
    := shaper_frac_bits(out_bits_c, domain_l2_c, table_l2_c);
  constant value_bits_c: natural := out_bits_c - 1;
  constant delta_bits_c: natural := frac_bits_c + 2;
  constant word_bytes_c: natural
    := shaper_word_bytes(out_bits_c, domain_l2_c, table_l2_c);

  constant full_scale_c: unsigned(value_bits_c-1 downto 0) := (others => '1');
  constant beyond_zero_c: unsigned(in_bits_c-1 downto magnitude_bits_c)
    := (others => '0');

  type state_t is (
    ST_TAKE,
    ST_MAGNITUDE,
    ST_FETCH,
    ST_SCALE,
    ST_SUM,
    ST_SIGN,
    ST_PUT
    );

  type regs_t is
  record
    state: state_t;
    taken: frame_t;
    made: frame_t;
    channel: natural range 0 to max_channel_count_c-1;
    last, block_start, error: std_ulogic;

    magnitude: unsigned(in_bits_c-1 downto 0);
    negative: std_ulogic;
    -- Magnitude past the top of the table, where the curve has
    -- nothing left to say
    beyond: std_ulogic;
    frac: unsigned(frac_bits_c-1 downto 0);
    base: unsigned(value_bits_c-1 downto 0);
    product: unsigned(delta_bits_c+frac_bits_c-1 downto 0);
    value: unsigned(value_bits_c-1 downto 0);
  end record;

  signal r, rin: regs_t;

  signal rom_read_s: std_ulogic;
  signal rom_address_s: unsigned(table_l2_c-1 downto 0);
  signal rom_data_s: std_ulogic_vector(8*word_bytes_c-1 downto 0);

begin

  shape_check: nsl_synthesis.assertion.synth_assert
    generic map(
      message_c => "A saturator carries the channels and sideband it was "
      & "given, works on signed samples, and needs an incoming stream "
      & "wider than the outgoing one by the headroom its table covers",
      condition_c => in_config_c.channel_count = out_config_c.channel_count
      and in_config_c.sideband_bits = out_config_c.sideband_bits
      and in_config_c.coding = CODING_SIGNED
      and out_config_c.coding = CODING_SIGNED
      and in_bits_c > magnitude_bits_c
      )
    port map(
      unused_i => '0'
      );

  curve: nsl_memory.rom.rom_bytes
    generic map(
      implementation_c => nsl_memory.rom.ROM_BLOCK,
      word_addr_size_c => table_l2_c,
      word_byte_count_c => word_bytes_c,
      contents_c => shaper_curve(shape_c, knee_c, out_bits_c,
                                 domain_l2_c, table_l2_c)
      )
    port map(
      clock_i => clock_i,
      read_i => rom_read_s,
      address_i => rom_address_s,
      data_o => rom_data_s
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
      r.magnitude <= (others => '0');
      r.negative <= '0';
      r.beyond <= '0';
      r.frac <= (others => '0');
      r.base <= (others => '0');
      r.product <= (others => '0');
      r.value <= (others => '0');
    end if;
  end process;

  transition: process(r, in_i, out_i, rom_data_s) is
    variable sample: signed(in_bits_c downto 0);
    variable magnitude: unsigned(in_bits_c-1 downto 0);
    variable delta: unsigned(delta_bits_c-1 downto 0);
    variable step: unsigned(delta_bits_c-1 downto 0);
    variable sum: unsigned(value_bits_c downto 0);
    variable signed_value: signed(out_bits_c-1 downto 0);
  begin
    rin <= r;

    sample := resize(signed(r.taken(r.channel).sample(in_bits_c-1 downto 0)),
                     in_bits_c+1);
    if sample < 0 then
      magnitude := unsigned(resize(-sample, in_bits_c));
    else
      magnitude := unsigned(resize(sample, in_bits_c));
    end if;

    -- The point the table gave and the way it was going from there,
    -- packed one after the other in a word.
    delta := unsigned(rom_data_s(value_bits_c+delta_bits_c-1 downto value_bits_c));
    -- How far along that way the magnitude fell
    step := r.product(r.product'left downto frac_bits_c);
    sum := resize(r.base, sum'length) + resize(step, sum'length);

    if r.negative = '1' then
      signed_value := -signed(resize(r.value, out_bits_c));
    else
      signed_value := signed(resize(r.value, out_bits_c));
    end if;

    case r.state is
      when ST_TAKE =>
        if is_valid(in_config_c, in_i) then
          rin.taken <= frame(in_config_c, in_i);
          rin.last <= to_logic(is_last(in_config_c, in_i));
          rin.block_start <= to_logic(is_block(in_config_c, in_i));
          rin.error <= to_logic(is_error(in_config_c, in_i));
          rin.channel <= 0;
          rin.state <= ST_MAGNITUDE;
        end if;

      when ST_MAGNITUDE =>
        rin.negative <= to_logic(sample < 0);
        rin.magnitude <= magnitude;
        rin.state <= ST_FETCH;

      when ST_FETCH =>
        rin.beyond <= to_logic(r.magnitude(in_bits_c-1 downto magnitude_bits_c)
                               /= beyond_zero_c);
        rin.frac <= r.magnitude(frac_bits_c-1 downto 0);
        rin.state <= ST_SCALE;

      when ST_SCALE =>
        rin.base <= unsigned(rom_data_s(value_bits_c-1 downto 0));
        rin.product <= delta * r.frac;
        rin.state <= ST_SUM;

      when ST_SUM =>
        if r.beyond = '1' then
          rin.value <= full_scale_c;
        else
          rin.value <= sum(value_bits_c-1 downto 0);
        end if;
        rin.state <= ST_SIGN;

      when ST_SIGN =>
        rin.made(r.channel).sideband <= r.taken(r.channel).sideband;
        rin.made(r.channel).sample
          <= to_sample(unsigned(signed_value), CODING_SIGNED);

        if r.channel = channels_c-1 then
          rin.state <= ST_PUT;
        else
          rin.channel <= r.channel + 1;
          rin.state <= ST_MAGNITUDE;
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

    rom_read_s <= to_logic(r.state = ST_FETCH);
    rom_address_s <= r.magnitude(magnitude_bits_c-1 downto frac_bits_c);
  end process;

end architecture;
