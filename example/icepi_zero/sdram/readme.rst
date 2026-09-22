=============
SDRAM bringup
=============

RAM part
========

**Winbond W9825G6KH** -- 256 Mbit, 4 banks x 8K rows x 512 columns x
16 bits, on an ECP5 (``LFE5U-25F-6BG256C``) through Diamond.

Its access time is 18 ns, so the CAS latency the timing package
resolves is **2** between about 55 and 111 MHz, and 3 above that.
Below 55 MHz it would resolve to 1, which the init script refuses --
the part table saying no to a clock the part cannot be driven at.

IOs
===

The PHY is portable.  One phase and one edge per controller cycle maps
a DFI slot straight onto a pin, so there is no serialising to do and
no strobe to place, and a fabric needs nothing from its vendor but the
block that forwards a clock.  ECP5 gained that block
(``nsl_io.ddr.ddr_output``, an ``ODDRX1F``); everything else is the
same RTL any backend would get.

The forwarded clock goes out half a period behind the controller's, so
the part samples the pins in the middle of the window they are held
for.

Read data is caught on the falling edge. With the clock forwarded half
a period behind, the read eye sits astride the launching clock's own
edges and neither lands in it.  The falling edge is near enough the
middle.  Both halves were confirmed in simulation by breaking them.

Running
=======

::

  gbs project build pnr
  acrobe chip -r ftdi-dk0gfmir/icepizero/jtag/chain program --run sdram.bit
  acrobe run walk.py 10

The number is how many walks to run, all of them out of one gatecap
session.

Open toolchain
==============

The same design, the same part and the same rate also build through
GHDL, yosys, nextpnr and ecppack::

  gbs project build pnr-yosys
  acrobe chip -r ftdi-dk0gfmir/icepizero/jtag/chain program --run sdram-yosys.bit
  acrobe run walk.py 10

Three things that chain needs and Diamond does not:

* The data pads are resolved in the top entity rather than through
  ``nsl_io.io.tristated_vector_io_driver``.  GHDL synthesis does not
  carry an inout across a hierarchy boundary: a child's inout port
  becomes an internal wire, the pin is emitted as an output, and what
  the fabric reads back is its own drive instead of what the part put
  on the wire.  Both halves of the bus die, and nothing says so.

* The placer's seed is pinned in the project file.  The fabric reaches
  about 80 MHz, which is what the design asks for, so whether the
  placer arrives depends on where it started.

* Nothing checks the bus.  nextpnr reads ``FREQUENCY`` out of the LPF
  and ignores the rest: ``CLOCK_TO_OUT``, ``INPUT_SETUP`` and ``BLOCK
  PATH`` pass unread, so the pin-level margins the table below is
  about are not covered by this flow.  What says the bus works is the
  walk.

Result
======

============  =========  ====================  ==========================  ===
``ram_hz_c``  tCK        fabric, ask / report  worst bus item              met
============  =========  ====================  ==========================  ===
100 MHz       10.0 ns    100 / 89.039 MHz      DQ out 3.773 vs 3.5 max     no
90 MHz        11.111 ns  90 / 87.352 MHz       read 10.177 vs 11.2 needed  no
83.333 MHz    12.0 ns    not buildable         --                          --
80 MHz        12.5 ns    80 / 81.446 MHz       read 11.313 vs 11.2 needed  yes
75 MHz        13.333 ns  75 / 80.959 MHz       read 11.379 vs 11.2 needed  yes
============  =========  ====================  ==========================  ===

So 80 MHz is the highest rate at which the fabric and the bus both
close, this is the current configuration.

The open chain lands in the same place from its own model: 80.84 MHz
against the 80 MHz ask, and the part walks clean at that rate.
