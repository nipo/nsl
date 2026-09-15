library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_video, nsl_synthesis;
use nsl_video.pixel_stream.all;

entity blender_color_key is
  generic(
    config_c: nsl_video.pixel_stream.config_t;
    key_color_c: natural := 0
    );
  port(
    overlay_i : in nsl_video.pixel_stream.master_t;
    overlay_o : out nsl_video.pixel_stream.slave_t;

    underlay_i : in nsl_video.pixel_stream.master_t;
    underlay_o : out nsl_video.pixel_stream.slave_t;

    out_o : out nsl_video.pixel_stream.master_t;
    out_i : in nsl_video.pixel_stream.slave_t
    );
end entity;

architecture beh of blender_color_key is

  constant key_c : nsl_video.pixel_stream.component_t
    := to_unsigned(key_color_c, nsl_video.pixel_stream.max_component_bits_c);

begin

  one_pixel_check: nsl_synthesis.assertion.synth_assert
    generic map(
      message_c => "Blending keys on one pixel at a time",
      condition_c => config_c.pixel_count = 1
      )
    port map(
      unused_i => '0'
      );

  index_check: nsl_synthesis.assertion.synth_assert
    generic map(
      message_c => "A colour index is a single component",
      condition_c => config_c.component_count = 1
      )
    port map(
      unused_i => '0'
      );

  blend: process(overlay_i, underlay_i, out_i) is
    variable overlay, underlay, blended: pixel_t;
    variable both_valid, taken: boolean;
  begin
    overlay := pixel(config_c, overlay_i);
    underlay := pixel(config_c, underlay_i);

    both_valid := is_valid(config_c, overlay_i) and is_valid(config_c, underlay_i);
    taken := both_valid and is_ready(config_c, out_i);

    if overlay(0) = key_c then
      blended := underlay;
    else
      blended := overlay;
    end if;

    overlay_o <= accept(config_c, ready => taken);
    underlay_o <= accept(config_c, ready => taken);

    -- Framing is the overlay's: both streams walk the same raster,
    -- and one of them has to say where it stands.
    out_o <= transfer(cfg => config_c,
                      pixel => blended,
                      valid => both_valid,
                      sof => is_sof(config_c, overlay_i),
                      last => is_last(config_c, overlay_i),
                      eof => is_eof(config_c, overlay_i),
                      error => is_error(config_c, overlay_i)
                               or is_error(config_c, underlay_i));
  end process;

end architecture;
