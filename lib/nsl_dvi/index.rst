=====
 DVI
=====

DVI output modules.

Video modes
===========

`mode <mode/>`_ states what a frame looks like -- active pixels and
lines, the blanking around them, the sync pulses inside it -- and the
clocks that frame calls for.

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
