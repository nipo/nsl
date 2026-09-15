library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_color, nsl_video, nsl_synthesis;
use nsl_video.pixel_stream.all;

entity colormap_lookup is
  generic(
    in_config_c : nsl_video.pixel_stream.config_t;
    out_config_c : nsl_video.pixel_stream.config_t
    );
  port(
    clock_i : in  std_ulogic;
    reset_n_i : in std_ulogic;

    palette_i : nsl_color.rgb.rgb24_vector(0 to 2**in_config_c.component_bits-1);

    in_i : in nsl_video.pixel_stream.master_t;
    in_o : out nsl_video.pixel_stream.slave_t;

    out_o : out nsl_video.pixel_stream.master_t;
    out_i : in nsl_video.pixel_stream.slave_t
    );
end entity;

architecture beh of colormap_lookup is

  subtype color_t is unsigned(in_config_c.component_bits-1 downto 0);

  -- What a beat carries besides its colour, and which travels with
  -- it through the lookup.
  type framing_t is
  record
    sof, last, eof, error: boolean;
  end record;

  type state_t is (
    ST_RESET,
    -- Nothing to hand out.
    ST_EMPTY,
    -- A pixel is on offer, and the input may be taken into it.
    ST_PIPE,
    -- A pixel is on offer and another colour waits behind it.
    ST_FULL
    );

  type regs_t is
  record
    state: state_t;
    color: color_t;
    color_framing: framing_t;
    pixel: nsl_color.rgb.rgb24;
    pixel_framing: framing_t;
  end record;

  signal r, rin: regs_t;

  function framing_of(m: master_t) return framing_t
  is
  begin
    return framing_t'(sof => is_sof(in_config_c, m),
                      last => is_last(in_config_c, m),
                      eof => is_eof(in_config_c, m),
                      error => is_error(in_config_c, m));
  end function;

begin

  one_pixel_check: nsl_synthesis.assertion.synth_assert
    generic map(
      message_c => "A palette is looked up one pixel at a time",
      condition_c => in_config_c.pixel_count = 1 and out_config_c.pixel_count = 1
      )
    port map(
      unused_i => '0'
      );

  index_check: nsl_synthesis.assertion.synth_assert
    generic map(
      message_c => "A colour index is a single component",
      condition_c => in_config_c.component_count = 1
      )
    port map(
      unused_i => '0'
      );

  regs: process(reset_n_i, clock_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_RESET;
    end if;
  end process;

  transition: process(r, palette_i, in_i, out_i) is
    variable color: color_t;
    variable valid, ready: boolean;
  begin
    rin <= r;

    color := resize(pixel(in_config_c, in_i)(0), color_t'length);
    valid := is_valid(in_config_c, in_i);
    ready := is_ready(out_config_c, out_i);

    case r.state is
      when ST_RESET =>
        rin.state <= ST_EMPTY;

      when ST_EMPTY =>
        if valid then
          rin.pixel <= palette_i(to_integer(color));
          rin.pixel_framing <= framing_of(in_i);
          rin.state <= ST_PIPE;
        end if;

      when ST_PIPE =>
        if ready then
          if valid then
            rin.pixel <= palette_i(to_integer(color));
            rin.pixel_framing <= framing_of(in_i);
          else
            rin.state <= ST_EMPTY;
          end if;
        elsif valid then
          rin.color <= color;
          rin.color_framing <= framing_of(in_i);
          rin.state <= ST_FULL;
        end if;

      when ST_FULL =>
        if ready then
          rin.pixel <= palette_i(to_integer(r.color));
          rin.pixel_framing <= r.color_framing;
          rin.state <= ST_PIPE;
        end if;
    end case;
  end process;

  moore: process(r) is
  begin
    in_o <= accept(in_config_c, ready => false);
    out_o <= transfer(cfg => out_config_c,
                      pixel => pixel_dontcare_c,
                      valid => false);

    case r.state is
      when ST_RESET =>
        null;

      when ST_EMPTY =>
        in_o <= accept(in_config_c, ready => true);

      when ST_PIPE | ST_FULL =>
        if r.state = ST_PIPE then
          in_o <= accept(in_config_c, ready => true);
        end if;

        out_o <= transfer(cfg => out_config_c,
                          pixel => to_pixel(out_config_c, r.pixel),
                          valid => true,
                          sof => r.pixel_framing.sof,
                          last => r.pixel_framing.last,
                          eof => r.pixel_framing.eof,
                          error => r.pixel_framing.error);
    end case;
  end process;

end architecture;
