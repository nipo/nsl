library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_audio, nsl_math, nsl_synthesis;
use nsl_audio.pcm.all;
use nsl_audio.pcm_stream.all;
use nsl_math.fixed.all;

entity pcm_iir_cascade is
  generic(
    config_c: nsl_audio.pcm_stream.config_t;
    stage_count_c: natural range 1 to work.iir.max_stage_count_c;
    coefficient_width_c: positive := 24;
    coefficient_fraction_bits_c: natural := 20;
    guard_bits_c: natural := 4
    );
  port(
    reset_n_i: in std_ulogic;
    clock_i: in std_ulogic;

    in_i: in nsl_amba.axi4_stream.master_t;
    in_o: out nsl_amba.axi4_stream.slave_t;

    out_o: out nsl_amba.axi4_stream.master_t;
    out_i: in nsl_amba.axi4_stream.slave_t;

    coefficients_i: in std_ulogic_vector(
      stage_count_c * work.iir.biquad_coefficient_count_c
      * coefficient_width_c - 1 downto 0);
    flush_i: in std_ulogic := '0'
    );
end entity;

architecture rtl of pcm_iir_cascade is

  constant sample_bits_c: natural := config_c.sample_bits;
  constant channel_count_c: natural := config_c.channel_count;
  constant state_count_c: natural
    := max_channel_count_c * work.iir.max_stage_count_c;

  subtype value_t is sfixed(sample_bits_c + guard_bits_c - 1
                            downto -coefficient_fraction_bits_c);
  subtype coefficient_t is sfixed(
    coefficient_width_c - coefficient_fraction_bits_c - 1
    downto -coefficient_fraction_bits_c);

  type value_vector_t is array(0 to state_count_c-1) of value_t;

  type coefficients_t is
  record
    b0: coefficient_t;
    b1: coefficient_t;
    b2: coefficient_t;
    a1: coefficient_t;
    a2: coefficient_t;
  end record;

  type state_t is (ST_TAKE, ST_LATCH, ST_B0, ST_B1, ST_B2, ST_A1,
                   ST_A2, ST_STORE, ST_PUT);

  type regs_t is
  record
    state: state_t;
    taken: nsl_amba.axi4_stream.master_t;
    made: frame_t;
    channel: natural range 0 to max_channel_count_c-1;
    stage: natural range 0 to work.iir.max_stage_count_c-1;
    section_input: value_t;
    accumulator: value_t;
    coefficients: coefficients_t;
    x1: value_vector_t;
    x2: value_vector_t;
    y1: value_vector_t;
    y2: value_vector_t;
  end record;

  signal r, rin: regs_t;

  function coefficient_at(coefficients: std_ulogic_vector;
                          stage: natural;
                          number: natural) return coefficient_t
  is
    constant low_c: natural
      := (stage * work.iir.biquad_coefficient_count_c + number)
      * coefficient_width_c;
  begin
    return coefficient_t(coefficients(low_c + coefficient_width_c - 1
                                      downto low_c));
  end function;

  function state_index(channel: natural; stage: natural) return natural
  is
  begin
    return channel * work.iir.max_stage_count_c + stage;
  end function;

  function pcm_value(sample: sample_t) return value_t
  is
  begin
    return resize(to_sfixed(signed(sample(sample_bits_c-1 downto 0))),
                  value_t'left, value_t'right);
  end function;

  function pcm_sample(value: value_t) return sample_t
  is
  begin
    return to_sample(
      unsigned(to_signed(resize_saturate(value, sample_bits_c-1, 0))),
      CODING_SIGNED);
  end function;

  function quantized_value(value: value_t) return value_t
  is
    constant sample_c: sample_t := pcm_sample(value);
  begin
    return resize(
      to_sfixed(signed(sample_c(sample_bits_c-1 downto 0))),
      value_t'left, value_t'right);
  end function;

begin

  parameter_check: nsl_synthesis.assertion.synth_assert
    generic map(
      message_c => "An IIR cascade requires signed PCM, a coefficient sign "
        & "bit and at least one integer coefficient bit",
      condition_c => config_c.coding = CODING_SIGNED
        and coefficient_fraction_bits_c + 2 <= coefficient_width_c
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
      r.taken <= transfer_defaults(config_c);
      r.made <= frame_zero_c;
      r.channel <= 0;
      r.stage <= 0;
      r.section_input <= (others => '0');
      r.accumulator <= (others => '0');
      r.coefficients.b0 <= (others => '0');
      r.coefficients.b1 <= (others => '0');
      r.coefficients.b2 <= (others => '0');
      r.coefficients.a1 <= (others => '0');
      r.coefficients.a2 <= (others => '0');
      r.x1 <= (others => (others => '0'));
      r.x2 <= (others => (others => '0'));
      r.y1 <= (others => (others => '0'));
      r.y2 <= (others => (others => '0'));
    end if;
  end process;

  transition: process(r, in_i, out_i, coefficients_i, flush_i) is
    variable input_frame_v: frame_t;
    variable history_index_v: natural range 0 to state_count_c-1;
    variable section_output_v: value_t;
  begin
    rin <= r;

    input_frame_v := frame(config_c, r.taken);
    history_index_v := state_index(r.channel, r.stage);
    section_output_v := quantized_value(r.accumulator);

    if flush_i = '1' then
      rin.state <= ST_TAKE;
      rin.taken <= transfer_defaults(config_c);
      rin.made <= frame_zero_c;
      rin.channel <= 0;
      rin.stage <= 0;
      rin.section_input <= (others => '0');
      rin.accumulator <= (others => '0');
      rin.x1 <= (others => (others => '0'));
      rin.x2 <= (others => (others => '0'));
      rin.y1 <= (others => (others => '0'));
      rin.y2 <= (others => (others => '0'));
    else
      case r.state is
        when ST_TAKE =>
          if is_valid(config_c, in_i) then
            rin.taken <= in_i;
            rin.made <= frame(config_c, in_i);
            rin.channel <= 0;
            rin.stage <= 0;
            rin.section_input <= pcm_value(
              frame(config_c, in_i)(0).sample);
            rin.state <= ST_LATCH;
          end if;

        when ST_LATCH =>
          rin.coefficients.b0 <= coefficient_at(
             coefficients_i, r.stage, work.iir.coefficient_b0_c);
          rin.coefficients.b1 <= coefficient_at(
             coefficients_i, r.stage, work.iir.coefficient_b1_c);
          rin.coefficients.b2 <= coefficient_at(
             coefficients_i, r.stage, work.iir.coefficient_b2_c);
          rin.coefficients.a1 <= coefficient_at(
             coefficients_i, r.stage, work.iir.coefficient_a1_c);
          rin.coefficients.a2 <= coefficient_at(
             coefficients_i, r.stage, work.iir.coefficient_a2_c);
          rin.state <= ST_B0;

        when ST_B0 =>
          rin.accumulator <= mul(r.section_input, r.coefficients.b0,
                                 value_t'left, value_t'right);
          rin.state <= ST_B1;

        when ST_B1 =>
          rin.accumulator <= add_saturate(
            r.accumulator,
            mul(r.x1(history_index_v), r.coefficients.b1,
                value_t'left, value_t'right));
          rin.state <= ST_B2;

        when ST_B2 =>
          rin.accumulator <= add_saturate(
            r.accumulator,
            mul(r.x2(history_index_v), r.coefficients.b2,
                value_t'left, value_t'right));
          rin.state <= ST_A1;

        when ST_A1 =>
          rin.accumulator <= resize_saturate(
            sub_extend(
              r.accumulator,
              mul(r.y1(history_index_v), r.coefficients.a1,
                  value_t'left, value_t'right)),
            value_t'left, value_t'right);
          rin.state <= ST_A2;

        when ST_A2 =>
          rin.accumulator <= resize_saturate(
            sub_extend(
              r.accumulator,
              mul(r.y2(history_index_v), r.coefficients.a2,
                  value_t'left, value_t'right)),
            value_t'left, value_t'right);
          rin.state <= ST_STORE;

        when ST_STORE =>
          rin.x2(history_index_v) <= r.x1(history_index_v);
          rin.x1(history_index_v) <= r.section_input;
          rin.y2(history_index_v) <= r.y1(history_index_v);
          rin.y1(history_index_v) <= r.accumulator;

          if r.stage = stage_count_c-1 then
            rin.made(r.channel).sample <= pcm_sample(r.accumulator);
            if r.channel = channel_count_c-1 then
              rin.state <= ST_PUT;
            else
              rin.channel <= r.channel + 1;
              rin.stage <= 0;
              rin.section_input <= pcm_value(
                input_frame_v(r.channel + 1).sample);
              rin.state <= ST_LATCH;
            end if;
          else
            rin.stage <= r.stage + 1;
            rin.section_input <= section_output_v;
            rin.state <= ST_LATCH;
          end if;

        when ST_PUT =>
          if is_ready(config_c, out_i) then
            rin.state <= ST_TAKE;
          end if;
      end case;
    end if;
  end process;

  in_o <= accept(config_c, r.state = ST_TAKE and flush_i = '0');

  mealy: process(r, flush_i) is
    variable formatted_v: nsl_amba.axi4_stream.master_t;
    variable output_v: nsl_amba.axi4_stream.master_t;
  begin
    formatted_v := transfer(
      cfg => config_c,
      frame => r.made,
      valid => r.state = ST_PUT and flush_i = '0');
    output_v := r.taken;
    output_v.data(0 to frame_bytes(config_c)-1)
      := formatted_v.data(0 to frame_bytes(config_c)-1);
    output_v.valid := formatted_v.valid;
    out_o <= output_v;
  end process;

end architecture;
