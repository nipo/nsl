======================
CYC1000 SDRAM bringup
======================

The whole of a Trenz CYC1000's memory written and read back from a
host, through ``nsl_ext_ram``'s SDRAM controller on a Cyclone 10 LP.

RAM part
========

**Winbond W9864G6JT** -- 64 Mbit, 4 banks x 4K rows x 256 columns x
16 bits, so 8 MiB, on a ``10CL025YU256C8G`` through Quartus Prime
24.1std.

Its datasheet sorts the part into two speed grades, ``-6`` and
``-6I``, and gives them one AC table between them: they differ in
temperature range and in nothing else, so there is no grade to
determine.  ``nsl_ext_ram.part``'s ``w9864g6jt_c`` is that table.

The CAS latency comes out of it as **2** at this rate.  The sheet
states the latency as a minimum period for each -- 7.5 ns at CL2, 6 ns
at CL3 -- and 15 ns is the access time both of those are the rounding
of; rounding it up against a 12.5 ns period gives 2.

A12 and A13 are commented out of Trenz's own pin assignments, and the
geometry is why: twelve row bits address a bank and the package does
not bond the other two.

Two clocks, and which is which
==============================

**The transport rides the 12 MHz oscillator.  The controller, the
walker and the panel ride the PLL.**

That is the arrangement, not an accident of it.  An instrument whose
own clock comes from the thing it measures cannot report that thing
being wrong: a PLL that came up at the wrong rate would take the link
down with it, and a dead link says nothing about why.  Here a wrong
PLL is a wrong number on a link that still answers.

It costs a crossing.  The rack's core is in the oscillator's domain
and the panel is in the memory clock's, so every control and status
word crosses between them through the resynchronisers the gatecap
shell carries.  Quartus times that crossing -- the two clocks share a
PLL, so it is not asynchronous to it -- and the design's worst setup
path is one of those words.

**Quartus recognises none of NSL's CDC attributes**, so those
crossings are unprotected against register merging.  Nothing here has
needed the lever, but it exists: ``set_instance_assignment -name
PRESERVE_REGISTER ON`` and ``-name DONT_MERGE_REGISTER ON`` on the
crossing registers.

IOs
===

The PHY is portable and needs one thing from the vendor: the block
that forwards a clock to a pin.  Cyclone 10 LP gained that as
``nsl_io.ddr.ddr_output`` on ALTDDIO_OUT, and
``example/trenz_tei0003/clock_check`` is where it was proved to move a
pin before this bench was allowed to depend on it.

The forwarded clock goes out half a period behind the controller's, so
the part samples the pins in the middle of the window they are held
for.  Read data is caught on the falling edge, which with that
forwarded clock is near enough the middle of the read eye.

``clocks.sdc`` states the memory bus against that forwarded clock
rather than cutting it: a generated clock on ``ram_clock_o``, inverted
because that is what a DDR output handed the two halves of a clock
makes; the datasheet's 1.5 ns of setup and 1 ns of hold as output
delays on everything driven; and its 6 ns access time and 3 ns output
hold as input delays on DQ.  Every one of those paths closes.

``pins.tcl`` sets ``RESERVE_ALL_UNUSED_PINS`` to ``AS INPUT
TRI-STATED``, and that is not optional.  A Cyclone drives an
unmentioned pin to ground, and this design leaves the accelerometer,
the ADC, the user header and four FT2232H pins alone, two of which the
FTDI drives as modem lines.

Running
=======

::

  gbs -C example/trenz_tei0003/sdram project build
  acrobe chip -r tei-ara41546/jtag/chain/0 program sdram.rbf
  PYTHONPATH=$HOME/projects/gatecap/host acrobe run walk.py 5

The number is how many walks to run, all of them out of one gatecap
session.  The link is the board's second FT2232H channel at 1 Mbaud,
the same transport ``../gatecap_uart`` brought up; ``walk.py`` sets
the line rate itself, because a resource path cannot state one.

Settings
========

============================  ================================
``ram_hz_c``                  80 MHz, tCK 12.5 ns
``capture_ck_c``              2
CAS latency                   2, resolved from the part table
``burst_length_l2_c``         3
``region_byte_l2_c``          23, the whole 8 MiB
============================  ================================

**capture_ck_c was swept, not chosen.**  Which falling edge the
part's answer lands on moves with the period, so one build carries one
value and the value is found by trying them.  At 80 MHz:

=================  ===========================================
``capture_ck_c``   result
=================  ===========================================
1                  every beat wrong, first read ``0xbe92``
2                  clean
3                  every beat wrong, first read ``0x2dff``
4                  every beat wrong, first read ``0xa04b``
=================  ===========================================

The failures are worth reading rather than counting: 4194304 beats
came back in every one of them, and the word in each is neither all
ones nor all zeroes.  The part was driving the bus the whole time and
the only thing wrong was when it was sampled.  Coming down the rate
ladder would move this figure, which is why it is swept at each rung
rather than carried down.

Timing
======

Closed at **80 MHz** on a ``-C8``, the slow grade, with nothing cut.
Worst slacks on the Slow 1200 mV 85 C model:

=========================  ========  =======  =========================
clock                      setup     hold     worst path
=========================  ========  =======  =========================
``clk12m``                 0.279 ns  0.398    a panel word crossing
                                              into the memory domain
PLL output, 80 MHz         1.515 ns  0.450    the same crossing, the
                                              other way
``ram_clk``, the pin       2.295 ns  5.820    DQ out against the
                                              forwarded clock
=========================  ========  =======  =========================

The read path is analysed under the PLL's own domain, since that is
where it is captured: DQ in to the capture register closes with 1.994
ns of setup over a 12.499 ns relationship.

5486 logic elements of 24624, 4338 registers, 49 pins, one PLL.

Result
======

::

  rack fingerprint 0x0032f013
  ram clock:    80000000 Hz  want    80000000 Hz      +0.0 ppm  ok
  built for 80000000 Hz, capture_ck_c 2
  --- at rest, walker held in reset
    0.0s  ready 0 busy 0 done 0  | aw 0 w 0 b 0 ar 0 r 0  | ...
    1.0s  ready 0 busy 0 done 0  | aw 0 w 0 b 0 ar 0 r 0  | ...
  --- walk 1
    0.3s  ready 1 busy 0 done 1  | aw 524288 w 4194304 b 524288
          ar 524288 r 4194304  | last aw 0x7ffff0 ar 0x7ffff0  | ...
  walk: 0.32 s to done, about 25.6M controller cycles
    48.8 cycles a transaction, written and read back, over 524288 of them
  walk 1: every location written and read back, PASSED
  ...
  --- 5 of 5 walks clean

524288 transactions of eight beats of two bytes is 8388608 bytes, and
``last aw 0x7ffff0`` is the last sixteen-byte transaction of an 8 MiB
part: the walk reaches the end of the device rather than of a window
into it.

0.32 s for 16 MiB of traffic is 52 MB/s, about 48.8 controller cycles
for a sixteen-byte transaction written and read back.

What had to be found
====================

**Quartus refuses an alias whose subtype has a null range**, and
``nsl_ext_ram.dfi`` had two: the functions that take an optional write
mask alias it into a known index direction, and the default is empty.
A constant declared from the argument copies position-wise, which is
what the alias gave, and takes a null range without complaint.  This
is the same gap ``nsl_data.crc`` hit before it; it is elaboration
time, so it costs a build rather than a board.

**The command counters do not clear with the run, and the first
reading of a session shows it.**  They are counted from the memory
domain's reset, so what a host sees before its first walk is whatever
the design did between configuration and the host arriving -- which is
a walk the control register started by itself, stopped partway
through.  That is the point of them: a bus that stops advancing with
these still moving is a part that is not answering, and one that stops
with these frozen is a controller that has stopped asking.

**The rate read immediately after configuration is a part-counted
one.**  The measurer counts over a whole second of its reference, so
the first published window is short and reads about 20 ppm low.  It is
exactly 80000000 Hz once a window has passed.
