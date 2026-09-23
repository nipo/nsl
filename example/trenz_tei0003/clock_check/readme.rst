===========================
CYC1000 PLL and DDR output
===========================

Two measurements on a Trenz CYC1000 (TEI0003, ``10CL025YU256C8G``),
both read from a host over the board's own serial port: the rate the
PLL comes up at, and whether the DDR output block moves a pin.

Neither can be told from a bitstream.  A PLL that elaborates, fits and
reports a nominal VCO frequency has proved nothing about silicon, and
a DDR output that silently forwards one of its two halves builds,
fits, meets timing and drives a constant.

The transport is the ``gatecap_uart`` bench's: the FT2232H's second
channel at 1 Mbaud, HDLC frames, an 8n1 UART.  **It rides the 12 MHz
oscillator and not the PLL.**

That is the rule every instrument on this board follows: an
instrument's clock must not come from the thing it measures.  A rack
riding the PLL reports the PLL's rate correctly by construction and
says nothing -- and a PLL that came up wrong would take the link down
with it, leaving the one situation the instrument exists for as the
one in which it is silent.  Here a wrong PLL is a wrong number on a
link that still answers.

What is measured
================

``fabric``
  The PLL output as the fabric sees it, counted against the
  oscillator.

``loopback``
  The same clock after ``nsl_io.ddr.ddr_output``, the header pin
  ``PIO_01`` and that pin's own input buffer.

``loopback`` is the whole point.  The block is handed the two
constant halves a forwarded clock is made of -- low while the clock is
high, high while it is low -- so the pin carries a square wave at the
*whole* clock rate.  An output register clocked by that same clock
cannot reach more than half of it, so a loopback reading that matches
``fabric`` is both halves of the period reaching the pad, and nothing
else produces that number.

The pin is a real bidirectional one: the output enable is the PLL's
lock rather than a constant, so the fitter builds a tri-state buffer
and an input buffer, and the rate is counted on what comes back
through the pad rather than on the net that drives it.  The fitter
report says ``bidir`` for F13 and places a ``ddio_outa`` cell on it.

The control bit ``still`` holds both halves at the same value, which
stops the pin.  A loopback rate that does not fall with it is a
measurer counting some other net, and the reading above would prove
nothing.

Building and programming
========================

::

  gbs -C example/trenz_tei0003/clock_check project build
  acrobe chip -r tei-ara41546/jtag/chain/0 program clock_check.rbf

2466 logic elements of 24624, 1865 registers, 12 pins and one PLL.
Timing closes on all three clocks; the worst setup slack is 0.296 ns,
on ``clk12m``.  That is not
the 83 ns period it sounds like: the 80 MHz domain and the 12 MHz one
come from the same PLL, so Quartus times the measurer's crossings
between them against the closest edge pair the two rates make, which
is 12.5 ns apart.

Result
======

::

  PYTHONPATH=$HOME/projects/gatecap/host acrobe run rates.py

::

  rack fingerprint 0x03bcee91
  locked 1
  --- DDR output driving the pin
     fabric:    80000000 Hz  want    80000000 Hz      +0.0 ppm  ok
   loopback:    80000000 Hz  want    80000000 Hz      +0.0 ppm  ok
  --- both halves of the DDR output held equal
     fabric: 80000000 Hz
   loopback: 0 Hz

The PLL runs at 80.000000 MHz, to the hertz the measurer resolves:
the ratio 20/3 off a 12 MHz reference is exact, and the reference is
a crystal oscillator, so there is nothing for the PLL to be wrong by
that the measurement would not see.

The pin runs at the same rate, and stops when it is told to.
