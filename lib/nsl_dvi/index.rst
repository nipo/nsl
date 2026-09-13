=====
 DVI
=====

DVI output modules.

Video modes
===========

Modes live in `nsl_video.mode <../nsl_video/index.html>`_ and
`nsl_dvi.mode <mode/>`_ is the name DVI users know them by. A mode
states what a frame looks like -- active pixels and lines, the
blanking around them, the sync pulses inside it -- and the clocks
that frame calls for.

Two families state the remaining number differently. Broadcast modes
(CEA/HDMI) state a frame rate and the pixel clock follows from the
geometry; computer modes (VESA/DMT) state a pixel clock and the frame
rate follows. 1024x768 at "60 Hz" runs at 65 MHz, which is 60.004
frames per second, not 60, and `mode_build_clocked` is how such a
mode is stated. Either way a mode knows its pixel clock exactly,
which is what clock generation needs::

  constant mode_c : mode_t := mode_std_1280x720p50_c;

  constant video_config_c : pll_config_t := pll_config(
    input_hz => 50_000_000,
    o0 => pll_output(serial_clock_hz(mode_c)),
    o1 => pll_output(pixel_clock_hz(mode_c)));

`serial_clock_hz` is five times the pixel clock: DVI carries ten bits
per pixel per channel, sent on both clock edges.

HDMI shares these timings, and `nsl_hdmi.mode` is the name HDMI users
know them by.

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
