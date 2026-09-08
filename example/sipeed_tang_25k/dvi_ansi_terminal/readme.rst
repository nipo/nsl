========================
 DVI ANSI terminal demo
========================

A serial ANSI terminal on a DVI display. Bytes received on the UART at
115200 8N1 go through a FIFO into ``nsl_terminal.ansi.ansi_terminal``,
which drives a ``terminal_text_buffer`` rendered on the DVI output
(XGA 1024x768, J4 Pmod). Engine replies (cursor position, device
attributes) go back out on the UART transmitter.

The screen is 85x48 characters with the 16-color ANSI palette and
underline. Supported: cursor motion and positioning, display and line
erase, SGR attributes, insert/delete of characters and lines, scroll
regions, a blinking cursor (driven from the on-board blinker), and
device-status/attribute replies. See the ``nsl_terminal.ansi`` package
for the full sequence list.

The FTDI second channel is wired to the FPGA UART. On this host it
enumerates as ``/dev/cu.usbserial-...``.

A low-speed USB keyboard on the dock USB-A port makes it a complete
terminal: keystrokes go through ``nsl_usb.hid_host`` (boot-protocol
host, typematic repeat, VT escape sequences for arrows and function
keys, alt as an escape prefix) and out on the UART transmitter,
behind engine replies.  Local echo follows the SRM mode: off by
default (the host is expected to echo), ``CSI 12 l`` loops
keystrokes onto the screen, ``CSI 12 h`` turns that off again.

Driving it
==========

``demo.py`` (pyserial) plays scenes exercising the engine::

  ./demo.py                       # static showcase (banner, colors, attributes, cursor)
  ./demo.py --scene edit          # insert/delete character and line editing
  ./demo.py --scene region        # fixed header/footer, scrolling middle band
  ./demo.py --scene boxes         # nested filled rectangles
  ./demo.py --scene spectrum      # the 16-color palette
  ./demo.py --scene scroll        # ring-scroll stress
  ./demo.py --scene query         # send DSR/DA and print the replies
  ./demo.py --text '\e[1;32mhi'   # send arbitrary text, \e is ESC

Anything that emits ANSI works too, e.g. ``ls --color=always`` or
``git log --oneline --color=always`` redirected to the port.

Bitstream
=========

Build with ``gbs project build``; the ``.fs`` lands in
``gbs-build/synthesis/``. It targets the Sipeed Tang 25k (GW5A-25).
