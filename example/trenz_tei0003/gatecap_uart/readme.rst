=================================
CYC1000 serial gatecap transport
=================================

A gatecap rack on a Trenz CYC1000 (TEI0003, ``10CL025YU256C8G``),
reached from a host over the board's own USB connector.  It is the
first Altera design in this tree that a host can talk to: a panel of
four signals and a clock-rate block, behind an 8n1 UART carrying HDLC
frames.

There is no PLL and no external clock.  The 12 MHz oscillator on
``CLK12M`` clocks the transport, the instruments and the user logic
alike.

What the panel carries
======================

Small on purpose, and every part of it answers a question a bring-up
asks:

``scratch`` / ``scratch_back``
  A control word the host writes, wired in the fabric to a status word
  the host reads.  A round trip that matches has crossed the register
  file, so the link is not echoing and the rack is decoding addresses.

``ticks``
  A free-running counter off the 12 MHz pin.  A readback that moves
  says the design is clocked and the answer is live.

``ping`` / ``ping_count``
  A tick output wired to a tick input.  The same round trip taken
  through the panel's event path rather than through its registers.

``led``, ``button``
  Seven LEDs the host drives and the user button.  LED8 is not on the
  panel: it is bit 22 of the counter, so the board says whether it is
  clocked before any host has talked to it.

``rates``
  A ``gatecap.clock_measurer`` watching the oscillator against itself.
  The answer is known in advance, which is what makes it a check that
  the block, the transport and the clock are all running -- and it is
  the instrument the next design's PLL will be read with.

Building
========

::

  gbs -C example/trenz_tei0003/gatecap_uart project build

2368 logic elements of 24624, 1783 registers, 12 pins, no PLL.  Timing
closes with 70.3 ns of setup slack on an 83.3 ns period.

Programming
===========

The board's FT2232H holds two channels.  The first is the JTAG the
part is configured through, and acrobe reaches the part on it as
``tei-ara41546/jtag/chain/0`` -- the tail of the adapter name is the
board's USB serial number, so another board is another name.

**acrobe configures a Cyclone from a raw bitstream, not from a
``.sof``.**  The project asks gbs for a ``quartus-rbf`` output for
that reason, and that is the file to hand over::

  acrobe chip -r tei-ara41546/jtag/chain/0 program gatecap_uart.rbf

::

  Target: SRAM config of 10CL025Y  Loadable: config
  config: 0/718569 [00:00<?, ?B/s]
  Done.

The ``.sof`` beside it is for Quartus's own tools.  Do not reach for
it here: acrobe refuses it, and says so.

Talking to it
=============

The second channel is wired into the fabric as six plain pins, two of
which are this UART.  Linux binds ``ftdi_sio`` to it and it coexists
with acrobe's JTAG on the first channel: do not detach it.

::

  PYTHONPATH=$HOME/projects/gatecap/host acrobe run panel.py

::

  port tty-usb-Arrow_Arrow_USB_Blaster_TEI0003_ARA41546-if01-port0/serial at SerialConfig(baud=1000000, data_bits=8, parity=<Parity.NONE: 'none'>, stop_bits=<StopBits.ONE: 1>, flow_control=<FlowControl.NONE: 'none'>)
  rack fingerprint 0x00d2e50c
    block bridge
    block enumerator
    block rates
    block panel
    block registers
  rates {'board': 12000000}
  scratch 0x00000000 -> scratch_back 0x00000000  ok
  scratch 0xdeadbeef -> scratch_back 0xdeadbeef  ok
  scratch 0x5a5a5a5a -> scratch_back 0x5a5a5a5a  ok
  scratch 0xffffffff -> scratch_back 0xffffffff  ok
  ticks 148861276 -> 155063104, 6201828 in about half a second
  ping_count 0 -> 5 after 5 strobes
  button 1

6201828 ticks of a 12 MHz clock is 0.517 seconds, which is what an
``asyncio.sleep(0.5)`` with two register reads around it costs.

The rack path
-------------

::

  tty-usb-Arrow_Arrow_USB_Blaster_TEI0003_ARA41546-if01-port0/serial/hdlc/addr00/gatecap

The first segment is the adapter acrobe names after the udev by-id
link, so it carries the board's USB serial number and survives a
replug -- unlike ``/dev/ttyUSB4``, which does not.  The three after it
are the byte pipe, the HDLC framing the transport wraps its frames in,
and the rack.  Any unique substring of the adapter name works in its
place, so ``ARA41546/serial/hdlc/addr00/gatecap`` reaches the same
rack.

**A resource path cannot state a line rate.**  acrobe configures a
serial port through its serial-port interface, and a path option is
parsed and then silently dropped.  Worse, acrobe only clears the
kernel's line discipline when a configuration is applied, so a port
nobody configured is still at 9600 baud, canonical, echoing -- and
HDLC over it does nothing at all.  ``panel.py`` therefore resolves the
``.../serial`` node and applies ``SerialConfig(baud=1000000)`` before
it opens the session.  ``stty -F /dev/ttyUSBn 1000000 raw -echo``
beforehand does the same job for a one-off.

A ``Session.reconnect()`` tears that node down and spawns a fresh one
at kernel defaults, so the rate has to be re-applied after every
reconnect.

Baud rate
=========

1 Mbaud, and both ends divide exactly:

* the fabric's clock is 12 MHz, and ``nsl_uart``'s receiver counts
  whole clock cycles per bit -- there is no oversampling, so the only
  requirement is at least four cycles a bit.  12 is exact and well
  clear of the floor;
* the FT2232H's baud generator divides 12 MHz too, so 1 Mbaud is
  divisor 12 with no fractional part.

There is therefore no rate error at all on this link, which is a
better place to be than 115200's 0.16 %.  A slower design would want
115200; this one has no reason to.

Pinout
======

Taken from ``../pinout/TEI0003_pin_assignments.tcl``, Trenz's own
file.

**BDBUS0 is the FPGA's input and BDBUS1 its output**, as a standard
FT2232H UART channel has it: BDBUS0 is the FTDI's TXD and BDBUS1 its
RXD.  This worked first try on the real board and needed no swap.

=========  =========================  ========================
Signal     Pin                        Note
=========  =========================  ========================
CLK12M     M2                         the only clock
BDBUS0     R7                         ``uart_rx_i``, FTDI TXD
BDBUS1     T7                         ``uart_tx_o``, FTDI RXD
LED1-LED8  M6 T4 T3 R3 T2 R4 N5 N3    LED8 is the heartbeat
USER_BTN   N6                         reads 1 when not pressed
=========  =========================  ========================

``pins.tcl`` also sets ``RESERVE_ALL_UNUSED_PINS`` to ``AS INPUT
TRI-STATED``.  A Cyclone drives an unmentioned pin to ground by
default, and this part reaches an SDRAM, an accelerometer and the four
channel-B pins this design leaves alone, two of which the FT2232H
drives as modem lines.

What surprised us
=================

Three Quartus behaviours cost this bring-up its afternoon.  All three
are written up in ``doc/architecture_notes/altera/``; the short form:

**A control/status panel with no tick signal will not elaborate.**
Its shell takes two zero-length array generics, and Quartus refuses a
null array generic with a message about a string literal, on a line
past the end of an unrelated file.  The panel here carries a tick pair
it does not otherwise need.

**The link came up, enumerated, and lied.**  The first bitstream
answered every read from address zero and failed every write, so the
rack enumerated, reported a plausible fingerprint, measured the board
clock at 3.97 GHz and returned descriptor ROM for every panel
register.  The cause was in ``nsl_amba.stream_apb``: the function that
assembles the APB address a byte at a time left the bytes it was not
writing at their incoming value, and Quartus builds a bit like that
from a register and a latch clocked by the byte index -- which is
combinational.  Assigning every bit on every path fixes it, and the
address register is a register again.  Nothing in the build warned
about it in terms anyone would act on: it met timing with 70 ns to
spare.

**Quartus's VHDL analyser is loose about visibility.**  A use clause
naming a type does not bring its enumeration literals along, and a
literal written as an expanded name is not found either -- both legal
VHDL, both accepted everywhere else in this tree, and both present in
``nsl_memory.rom`` and ``nsl_uart.serdes`` before this design.
