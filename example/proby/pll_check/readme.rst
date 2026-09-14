==========================
 Clock manager phase check
==========================

Goal
====

The Spartan-6 half of the Series-6/7 check. Same question as
`example/digilent_arty_z7/pll_check`, on the older block: are the
rates the elaboration-time solver picks the rates the board makes,
and is a phase offset a *delay* of the output by that fraction of its
own cycle?

Everything is read over the chip's own TAP, through a gatecap rack,
on the Proby's FTDI.

Clock plan
==========

::

  DCM    12 MHz crystal  x27 /9  -> 36 MHz   rack clock
  PLL    36 MHz PFD      x27     -> 972 MHz VCO
           /81 -> 12 MHz   phase 0
           /81 -> 12 MHz   phase 1/4
           /81 -> 12 MHz   phase 1/2
           /81 -> 12 MHz   phase 3/4
           /20 -> 48.6 MHz logic analyzer sample clock
           /12 -> 81 MHz

**The DCM is not decoration.** A Spartan-6 PLL compares at 19 MHz and
up, and the board's crystal is at 12. Until the part tables stated
the phase detector window, the solver would happily have mapped the
crystal straight onto the PLL and built something out of spec. It now
refuses, and the DCM's synthesizer -- which has no phase detector on
that path -- carries the reference up first.

**The phase offsets are near the block's limit.** Three quarters of a
divide-by-81 output is 486 eighths of a VCO cycle, against the 511
the shifter holds in its six bits of whole cycles and three of
eighths. A divider much deeper than this cannot carry a
three-quarter shift at all, whatever the grid says.

**The two rates are deliberately incommensurate.** 48.6 MHz over
12 MHz is 81 over 20 in lowest terms, so a sample lands on 81
distinct points of the 12 MHz cycle before the pattern repeats,
resolving an edge to a little over four degrees.

The four shifted clocks reach the analyzer raw, as gatecap wants.
Unlike the Arty design, the probe copy is taken *ahead* of the global
buffer: a Spartan-6 global buffer may not drive a data pin, and MAP
stops rather than warning about it. The four probe routes are then
ordinary interconnect, no longer matched to one another, which is a
nanosecond or so of skew against the twenty a quarter cycle is worth.
The buffered copies still feed the rate measurer, where they drive
clock pins and nothing else.

The rack itself rides the crystal, not anything the clock managers
make. An instrument that only answers when its subject works tells
you nothing when the subject does not; this way a clock that never
starts reads zero, and the status panel says why.

Building and loading
====================

::

  gbs project build
  acrobe chip -r proby-0/jtag-int/chain -t 0 program --run pll_check.bit

The user LED, active low, blinks off the 12 MHz output, so a board
that stays dark has not locked.

The user button is read but does nothing: it sits at one with nothing
pressed on this board, so putting it in the reset path holds the
clock managers in reset for good. It is on the status panel as an
observation.

Checking it
===========

The rack is at
``proby-0/jtag-int/chain/0/bnoc_continuous_transport/gatecap``::

  acrobe gatecap -r <path> info
  acrobe run rates.py
  acrobe run phase.py

The panel carries ``user_btn``, ``startup_reset_n``, ``ref_locked``
and ``phase_locked``, which is what to read first when a rate comes
back zero.

Expect 90, 180 and 270 degrees, in that order. Coming out descending
would mean the block advances where the library promises a delay.

Measured
========

On a Proby, ISE 14.7, every rate exact to the hertz::

  p0, p90, p180, p270  12 MHz     dcm_36m    36 MHz
  sample            48.6 MHz      f81m       81 MHz

::

   p0:    0.00 deg
  p90:   90.16 deg
 p180:  180.03 deg
 p270:  272.34 deg

Ascending, so **a positive CLKOUTx_PHASE delays the output** on a
Spartan-6 PLL as it does on Series-7. The two and a third degrees on
p270 repeat to a hundredth across captures: that is the fixed routing
delay of one probe, not jitter, and it is the price of taking the
probe copy ahead of the global buffer. It is well inside the four
degrees the sampling grid is worth.
