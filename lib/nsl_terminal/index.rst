==========
 Terminal
==========

Text terminal emulation.

* `ANSI/ECMA-48 terminal engine <ansi>`_

ANSI terminal engine
====================

``nsl_terminal.ansi.ansi_terminal`` turns a byte stream (typically a
UART) into screen contents, driving the user port of a text buffer
memory such as ``nsl_dvi.terminal.terminal_text_buffer``. Any display
that exposes such a buffer (DVI, OLED, LCD) is then a terminal.

Architecture
------------

The engine is split into a complete parser and a partial execute
table. The ECMA-48 parser frames every escape sequence class (``ESC``,
``CSI`` with parameters and private markers, ``OSC``/``DCS``/... string
sequences), so unsupported sequences are recognised and discarded
cleanly instead of printing as garbage. The execute table then grows
one sequence at a time without touching the parser.

Data path
---------

* Input: a ready/valid byte stream. Multi-cycle operations (fills,
  in-place copies, replies, cursor draws) back-pressure the input.
* Output: the text buffer user port (address, write, cell contents),
  plus a read-back path the engine needs for the cursor and in-place
  editing. ``read_latency_c`` matches the buffer read latency.
* ``row_offset_o`` drives the buffer ring base: scrolling a full-screen
  region rolls the ring (offset +/- 1 and clear one row) rather than
  copying the whole screen.
* A reply byte stream answers device queries (cursor position, device
  attributes), typically fed back to the host UART transmitter.

Colors are 4-bit indices: 0-7 the standard ANSI colors, 8-15 the
bright variants (SGR bold or 90-107).

Supported sequences
-------------------

See the ``nsl_terminal.ansi`` package header for the authoritative
list. In summary: C0 controls, cursor motion and positioning, display
and line erase with background color, SGR attributes (16 colors,
underline, reverse, bold), save/restore, insert/delete of characters
and lines, scroll regions (DECSTBM), cursor show/hide and blink, and
device status / attribute replies. Origin mode (DECOM) is not
implemented; cursor positioning is absolute and only scrolling honors
the margins.

Backing memory
--------------

The buffer is written and read from the terminal clock domain and read
again from the video clock domain: one writer, two readers in two
clock domains. Served from a single ``ram_2p_homogeneous`` with a
registered output, the write+read term port and the video read port
map to one true dual-port block RAM. The engine never reads and writes
the buffer in the same cycle.
