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

The four shifted clocks reach the analyzer raw, as gatecap wants, and
ride the global network on their way, which is what keeps their
delays matched.

Building and loading
====================

::

  gbs project build
  acrobe chip -r proby-0/jtag-int/chain -t 0 program --run pll_check.bit

**The build does not go through yet.** XST reads its source list in
order and analyses as it goes, and gbs emits the generated gatecap
library after ``work``, so the top level is compiled before the
package it instantiates::

  Cannot find <pll_check> in library <gatecap_generated>

Moving the ``work`` line of ``gbs-build/synthesis/syn/source_list.txt``
to the end and rerunning ``xst -ifn command.xst`` by hand synthesizes
the design with no errors, PLL_BASE and DCM_SP both inferred, so this
is an ordering matter and nothing about the design. Vivado is
unaffected: it elaborates by dependency rather than by list order.

The user LED, active low, blinks off the 12 MHz output, so a board
that stays dark has not locked. The user button resets both clock
managers.

Checking it
===========

The rack is at
``proby-0/jtag-int/chain/0/bnoc_continuous_transport/gatecap``::

  acrobe gatecap -r <path> info
  acrobe run rates.py
  acrobe run phase.py

Expect 90, 180 and 270 degrees, in that order. Coming out descending
would mean the block advances where the library promises a delay.
