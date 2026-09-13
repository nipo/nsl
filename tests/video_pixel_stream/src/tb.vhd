library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_video, nsl_color, nsl_data, nsl_amba, nsl_simulation;
use nsl_video.mode.all;
use nsl_video.pixel_stream.all;
use nsl_color.rgb.all;
use nsl_data.text.all;

entity tb is
end entity;

architecture arch of tb is

  constant rgb888_c: config_t := config(pixels => 1);
  constant rgb888x4_c: config_t := config(pixels => 4, keep => true);
  constant rgb101010_c: config_t := config(pixels => 1, component_bits => 10);
  constant mono4_c: config_t := config(pixels => 4, components => 1, component_bits => 4);

  constant rgb888_stream_c: nsl_amba.axi4_stream.config_t := as_stream_config(rgb888_c);
  constant rgb888x4_stream_c: nsl_amba.axi4_stream.config_t := as_stream_config(rgb888x4_c);

begin

  main: process
    variable m: master_t;
    variable p: pixel_vector(0 to 3);
    variable q: pixel_t;
    variable c: nsl_color.rgb.rgb24;
    variable kv: std_ulogic_vector(0 to 11);
  begin
    -- A geometry states what a pixel stream needs of a mode, and
    -- nothing of what the wire needs

    assert geometry(mode_std_1280x720p50_c)
      = geometry(1280, 720)
      report "Bad 720p geometry"
      severity failure;
    assert x_width(geometry(1280, 720)) = 11
      report "Bad x width"
      severity failure;
    assert y_width(geometry(1280, 720)) = 10
      report "Bad y width"
      severity failure;
    assert pixel_count(geometry(1280, 720)) = 921600
      report "Bad frame pixel count"
      severity failure;

    -- Beat layout follows the component count and width

    assert pixel_bytes(rgb888_c) = 3
      report "Bad rgb888 pixel size"
      severity failure;
    assert pixel_bytes(rgb101010_c) = 6
      report "Bad rgb101010 pixel size"
      severity failure;
    assert pixel_bytes(mono4_c) = 1
      report "Bad mono4 pixel size"
      severity failure;
    assert rgb888x4_stream_c.data_width = 12
      report "Bad four-pixel beat width"
      severity failure;

    -- A stream is always framed: last is what states a line boundary

    assert rgb888_stream_c.has_last
      report "Stream must carry last"
      severity failure;
    assert rgb888_stream_c.user_width = user_width_c
      report "Bad user width"
      severity failure;

    -- Framing bits survive a round trip, and mean nothing to each
    -- other

    m := transfer(rgb888_c, to_pixel(rgb888_c, rgb24_red), sof => true);
    assert is_valid(rgb888_c, m)
      report "Beat should be valid"
      severity failure;
    assert is_sof(rgb888_c, m)
      report "Beat should open a frame"
      severity failure;
    assert not is_last(rgb888_c, m)
      report "Beat should not close a line"
      severity failure;
    assert not is_eof(rgb888_c, m) and not is_error(rgb888_c, m)
      report "Beat should not close a frame nor be in error"
      severity failure;

    m := transfer(rgb888_c, pixel_zero_c, last => true, eof => true, error => true);
    assert is_last(rgb888_c, m) and is_eof(rgb888_c, m) and is_error(rgb888_c, m)
      report "Beat should close a frame in error"
      severity failure;
    assert not is_sof(rgb888_c, m)
      report "Beat should not open a frame"
      severity failure;

    -- Colors survive a round trip through a beat

    m := transfer(rgb888_c, to_pixel(rgb888_c, rgb24_dark_orange));
    q := pixel(rgb888_c, m);
    c := to_rgb24(rgb888_c, q);
    assert c = rgb24_dark_orange
      report "rgb888 color did not survive"
      severity failure;

    -- Components wider than eight bits are left-aligned, so the
    -- eight bits an rgb24 holds come back unchanged

    m := transfer(rgb101010_c, to_pixel(rgb101010_c, rgb24_dark_orange));
    q := pixel(rgb101010_c, m);
    assert q(0) = x"03fc"
      report "Bad 10-bit red: " & to_string(std_ulogic_vector(q(0)))
      severity failure;
    c := to_rgb24(rgb101010_c, q);
    assert c = rgb24_dark_orange
      report "rgb101010 color did not survive"
      severity failure;

    -- Pixels keep their order inside a beat

    p(0) := to_pixel(rgb888x4_c, rgb24_red);
    p(1) := to_pixel(rgb888x4_c, rgb24_green);
    p(2) := to_pixel(rgb888x4_c, rgb24_blue);
    p(3) := to_pixel(rgb888x4_c, rgb24_white);
    m := transfer(rgb888x4_c, p);
    for i in 0 to 3
    loop
      q := pixel(rgb888x4_c, m, i);
      c := to_rgb24(rgb888x4_c, q);
      assert c = to_rgb24(rgb888x4_c, p(i))
        report "Beat pixel " & to_string(i) & " came back changed"
        severity failure;
    end loop;

    -- Keep is stated per pixel, and covers every byte of it.  A line
    -- whose length is not a multiple of the beat pixel count ends on
    -- such a beat.

    m := transfer(rgb888x4_c, p, keep => "1100", last => true);
    kv := keep(rgb888x4_c, m);
    assert kv = "111111000000"
      report "Bad partial beat keep: " & to_string(kv)
      severity failure;

    -- A single-component stream packs one pixel per byte

    p := (others => pixel_zero_c);
    p(0)(0) := x"0005";
    p(3)(0) := x"000a";
    m := transfer(mono4_c, p);
    q := pixel(mono4_c, m, 0);
    assert q(0) = x"0005"
      report "mono4 first pixel did not survive"
      severity failure;
    q := pixel(mono4_c, m, 3);
    assert q(0) = x"000a"
      report "mono4 last pixel did not survive"
      severity failure;

    nsl_simulation.control.terminate(0);
    wait;
  end process;

end architecture;
