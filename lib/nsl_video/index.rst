=======
 Video
=======

Video primitives shared by every wire protocol that carries a
raster.

Modes and geometries
====================

`mode <mode/>`_ states what a frame looks like -- active pixels and
lines, the blanking around them, the sync pulses inside it -- and the
clocks that frame calls for. `nsl_dvi.mode` and `nsl_hdmi.mode` are
the names DVI and HDMI users know the same package by.

A *geometry* is the part of a mode a pixel stream cares about: how
many pixels a line holds and how many lines a frame holds. Blanking
and clocks belong to the wire, so a frame generator or a panel driver
takes a geometry and never sees a mode::

  constant geometry_c : geometry_t := geometry(mode_std_1280x720p50_c);
