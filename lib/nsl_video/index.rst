=======
 Video
=======

Video primitives shared by every wire protocol that carries a
raster: what a frame looks like, and how pixels travel between
blocks.

Modes and geometries
====================

`mode <mode/>`_ states what a frame looks like -- active pixels and
lines, the blanking around them, the sync pulses inside it -- and the
clocks that frame calls for.

Two families state the remaining number differently. Broadcast modes
(CEA/HDMI) state a frame rate and the pixel clock follows from the
geometry; computer modes (VESA/DMT) state a pixel clock and the frame
rate follows. 1024x768 at "60 Hz" runs at 65 MHz, which is 60.004
frames per second, not 60, and `mode_build_clocked` is how such a
mode is stated. Either way a mode knows its pixel clock exactly.

A *geometry* is the part of a mode a pixel stream cares about: how
many pixels a line holds and how many lines a frame holds. Blanking
and clocks belong to the wire, so a frame generator or a panel driver
takes a geometry and never sees a mode::

  constant geometry_c : geometry_t := geometry(mode_std_1280x720p50_c);

Pixel streams
=============

`pixel_stream <pixel_stream/>`_ carries raster pixel data over
AXI4-Stream, the way `nsl_line_coding.ibm_8b10b_stream` carries
symbols: wire-level signals are plain `nsl_amba.axi4_stream` records,
so every stream block -- FIFOs, width adapters, routers -- works on a
pixel stream unchanged. The package adds a configuration record and
accessors expressing beats in pixels::

  constant pixels_c : config_t := config(pixels => 1);

A packet is a line. TLAST marks its last beat, and the first beat of
a line is the one following a TLAST. Three TUSER bits carry what a
line boundary cannot say by itself: SOF on the first beat of a frame,
EOF on the TLAST beat closing a frame, and ERROR on a TLAST beat
whose line is not to be trusted.

Lines rather than frames because that is the packet size every
generic stream block is built for: a FIFO holds one, a DMA descriptor
writes one, a scaler works on one. A frame-sized packet is millions
of beats and buys nothing.

The stream carries active pixels only. Blanking is a property of the
mode, not of pixel data, and shows up as beats where valid is
deasserted.

Framing travels with the pixels, so the *source* owns it: a generator
cycles through its own geometry and states where it is, and a sink
resynchronises to SOF when it starts. This is what lets a receiver
and a transmitter speak the same stream, and what lets a generic
stream block sit between them.

Rasters
=======

`raster <raster/>`_ holds the scan position so a frame generator does
not have to, and brings a stream and a raster together at either end
of a pipe.

Two shapes of generator call for two ways in. A generator that
answers what colour sits at a coordinate straight away uses
`pixel_stream_framer`, which states the coordinate and takes the
colour in the same cycle. One that reads a memory answers late and
uses `pixel_stream_requester` instead: it states that a frame and a
line open, asks for pixels, and waits for each. Nothing downstream
has taken anything meanwhile, so a late answer there costs time
rather than position.

At the other end, `pixel_stream_unframer` feeds a raster that owns
its own timing -- a DVI encoder, a panel driver. Framing travels with
the pixels and a wire-side raster cannot wait, so the two have to be
brought together: the unframer throws beats away until one opens a
frame, holds it until the raster opens a frame of its own, and hands
pixels over from there. `synced_o` states whether it holds.

From there it checks the two agree. A line or a frame the raster
opens while the stream has not closed the previous one shifts
everything that follows, so sync drops and the next frame starts
over. So does a pixel the raster asks for and the stream does not
hold, when the raster cannot wait: losing one pixel shifts the rest
of the frame, which is a loss of sync rather than a one-pixel glitch.
A panel driver can wait, states so with `raster_can_wait_c`, and
simply holds its serial interface instead.
