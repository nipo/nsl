================
 DVI scope demo
================

This example demonstrates the color-key overlay blender
(``nsl_dvi.blender.dvi_blender_color_key``).

A scope-style underlay (graticule and sine trace) and a
``terminal_labels_colormap`` overlay (title bar and status line) are
generated as color-index streams and blended in lockstep: overlay
pixels carrying the key color are replaced by the underlay. A single
colormap lookup then feeds the DVI encoder.

Video output is XGA 1024x768 at 60Hz with negative sync polarity, as
expected by 4:3 DVI displays of the early 2000s.

The DVI output is on the J4 Pmod, controls are on a BTN 4/4 Pmod on
J5. Sliders:

- slider 1 runs the horizontal scroll,
- slider 2 enables the graticule,
- slider 3 halves the trace amplitude,
- slider 4 hides the overlay (every label cell turns to the key
  color).

Push buttons, with auto-repeat while held:

- buttons 1/2 step the period count down/up (0.25 to 24 periods),
- buttons 3/4 pan the phase left/right, also while scrolling.

The status line shows the period count, the phase origin of the left
screen edge in degrees, and the slider states; the labels float over
the moving trace, showing the overlay is keyed, not boxed.
