=============
SRAM on Proby
=============

Bring up SRAM on Proby.

RAM Part
========

**Cypress CY7C1462AV25-200AXC** -- 36 Mbit, 2M x 18, 2.5 V, a
synchronous pipelined SRAM with no bus latency.

The board straps the burst counter's load input low.

A read command puts data on the bus two rising edges later; a write
command has its data taken from the bus two rising edges later.

The usable address space is 21 bits.  The pinout carries a
twenty-second line, which lands on a pin the die does not have at this
density; the design ties it low.

Clocks
======

::

  DCM    12 MHz oscillator  x27 /9  -> 36 MHz   PLL reference
  PLL    36 MHz PFD         x21 /6  -> 126 MHz  memory clock

DCM is there so that PLL accepts the input frequency.

Pins
====

The forwarded clock is half a period behind the controller's. The RAM
therefore samples in the middle of the window the pins are held for.

Output enable is tied asserted. RAM tri-states its bus for every cycle
that is not a read, whatever the pin says. Gating it would buy nothing.

Parity is generated and checked.

Constraints quirks
==================

``../pinout/ram.ucf`` is used to mark ``ram_clk`` as a global buffer
input.  It is an output, and a Spartan-6 global buffer may not drive a
data pin: MAP stops rather than warning.

``../pinout/jtag.ucf`` cannot be included alongside this design.  It
declares ``jtag_tck`` on P33 as LVCMOS33, and P33 sits in bank 3,
which every RAM pin sets to 2.5 V.

Running
=======

::

  gbs project build
  acrobe chip -r proby-0/jtag-int/chain program --run sram.bit
  acrobe run walk.py

The panel is on the memory clock, which is the domain every value it
carries is generated in.  The rate measurer is on the board oscillator
instead, and it is what tells a part that does not answer from a clock
that never started: a dead PLL reads zero there.

``run`` holds the walk in reset while it is low.  Dropping and raising
it starts a walk; the walker stops for good when it is done, by
design, so that edge is how the next one begins.

The LED is a heartbeat off the memory clock, active low, and says the
clock manager came up.

Result
======

Every iteration writes and reads back the whole 4 MiB part.

=========  =============  ============  ====================
rate       fabric slack   write setup   walk
=========  =============  ============  ====================
50 MHz     4.60 ns        7.32 ns       passed
100 MHz    1.47 ns        --            every beat wrong
100 MHz    0.58 ns        1.59 ns       passed, capture moved
114 MHz    1.13 ns        3.09 ns       passed
126 MHz    0.59 ns        3.02 ns       passed
132 MHz    0.56 ns        ~2.4 ns       passed, pad bound missed
=========  =============  ============  ====================

126 MHz is current bench config.
