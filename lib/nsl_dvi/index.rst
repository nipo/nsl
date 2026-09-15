=====
 DVI
=====

DVI output modules.

Video modes
===========

Modes live in `nsl_video.mode <../nsl_video/index.html>`_: a mode
states what a frame looks like -- active pixels and lines, the
blanking around them, the sync pulses inside it -- and the clocks
that frame calls for. A mode knows its pixel clock exactly, which is
what clock generation needs::

  constant mode_c : mode_t := mode_std_1280x720p50_c;

  constant video_config_c : pll_config_t := pll_config(
    input_hz => 50_000_000,
    o0 => pll_output(serial_clock_hz(mode_c)),
    o1 => pll_output(pixel_clock_hz(mode_c)));

`serial_clock_hz` is five times the pixel clock: DVI carries ten bits
per pixel per channel, sent on both clock edges. HDMI shares these
timings.

Pixels
======

Pixels reach the encoder over a `nsl_video.pixel_stream
<../nsl_video/index.html>`_, which states its own framing. The wire
cannot wait, so the raster inside the encoder owns the timing and the
stream follows it: the encoder locks onto the first frame the stream
opens and hands its pixels out from there, reporting on `synced_o`
whether it holds. Blanking colour goes out in place of pixels while
it does not::

  constant pixel_config_c : config_t := config(pixels => 1);

`channel_map_t` states which stream component each TMDS channel
carries, because a colourspace names its components in one order and
the wire sends them in another: RGB names red first and channel 0
carries blue, YCbCr names luma first and channel 0 carries Cb.
