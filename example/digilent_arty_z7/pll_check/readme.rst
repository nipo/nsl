==========================
 Clock manager phase check
==========================

Goal
====

Check on silicon what `nsl_clocking.pll` says it does on a Series-7
part: that the rates the elaboration-time solver picks are the rates
the board makes, that the input divider and the phase detector window
it now works from are right, and that a phase offset is a *delay* of
the output by that fraction of its own cycle.

Nothing leaves the chip but four LEDs. Everything is read over the
chip's own TAP, through a gatecap rack, on the board's onboard FTDI.

Clock plan
==========

The board's 125 MHz crystal on H16 feeds both clock managers::

  MMCM   /5 -> 25 MHz PFD -> x36 -> 900 MHz VCO
           /75 -> 12 MHz   phase 0
           /75 -> 12 MHz   phase 1/4
           /75 -> 12 MHz   phase 1/2
           /75 -> 12 MHz   phase 3/4
           /9  -> 100 MHz  rack clock

  PLL    /5 -> 25 MHz PFD -> x42 -> 1050 MHz VCO
           /12  -> 87.5 MHz  logic analyzer sample clock
           /7   -> 150 MHz
           /21  -> 50 MHz
           /42  -> 25 MHz
           /105 -> 10 MHz

Three things about that plan are the point of the exercise.

**The input divider has to be used.** 12 MHz off a 125 MHz crystal
needs a VCO that is a multiple of 300 MHz, and 125 times a whole
number never is. Dividing the reference by five puts 600, 900 and
1200 MHz in reach. The same goes for the PLL: every one of its five
rates divides 1050 MHz and nothing else in that block's window does.
Until the part tables stated the divider, neither mapping existed.

**The phase offsets move the mapping.** Undelayed, the solver would
take the top of the window, 1200 MHz over 100. Three quarters of a
divide-by-100 output is 600 eighths of a VCO cycle, and the shifter
holds 511 -- six bits of whole cycles and three of eighths. So it
walks down to 900 MHz over 75, which needs 450. A grid alone cannot
express that; the shifter's reach has to be modeled too.

**The two rates are deliberately incommensurate.** 87.5 MHz over
12 MHz is 175 over 24 in lowest terms, so a sample lands on 175
distinct points of the 12 MHz cycle before the pattern repeats. That
is what turns a plain logic analyzer into a phase meter good to a
175th of a cycle, two degrees, off a 16384-sample capture that covers
ninety-odd walks of the grid.

The four shifted clocks reach the analyzer raw, as gatecap wants, and
ride the global network on their way -- that is what keeps their
delays matched, so what is measured is the phase the block made and
not the routing.

The rack itself rides the board crystal, not anything the clock
managers make. An instrument that only answers when its subject works
tells you nothing when the subject does not; this way a clock that
never starts reads zero, which is the measurement. `clocks.xdc` cuts the two clock groups apart,
because that sampling is the measurement and there is nothing there
for the tool to time.

Building and loading
====================

::

  gbs -t gbs.builtin.vivado=vivado:2022.2 project build
  acrobe chip -r dig-003017a4c9e1/jtag/chain -t 0 program --run pll_check.bit

The PL is loaded on its own; no PS image is involved, and Vivado's
warning about a missing PS7 block is expected for a PL-only design.

LD0 and LD1 follow the two `locked_o`; LD2 blinks off the 12 MHz
output, so a board that says nothing at all has not locked.

Checking it
===========

The rack is at
``dig-003017a4c9e1/jtag/chain/0/bnoc_continuous_transport/gatecap``::

  acrobe gatecap -r <path> info
  acrobe run rates.py
  acrobe run phase.py

`rates.py` reads the clock measurer and compares every rate against
the plan above. `phase.py` captures the four shifted clocks and
reports their offsets: it gives every sample the phase of the cycle
it was taken at, sums those as unit vectors, and takes the argument.
Duty cycle, capture length and trigger instant all cancel in the
difference between two channels.

Expect 90, 180 and 270 degrees, in that order. Coming out descending
would mean the block advances where the library promises a delay.

Measured
========

On an Arty Z7-20, Vivado 2022.2, timing met with 8.1 ns of setup
slack::

  p0, p90, p180, p270  12 MHz     mmcm_100m  100 MHz
  sample            87.5 MHz       f150m      150 MHz
  f50m                50 MHz       f25m        25 MHz
  f10m                10 MHz

Every rate within six parts per million of the plan, on both blocks
and through an input divider of five -- and the same few ppm on all
ten, so the ratios between them are exact.

::

   p0:    0.00 deg
  p90:   89.67 deg
 p180:  179.94 deg
 p270:  269.93 deg

Ascending, and inside a degree of the request over repeated captures
-- the measurement grid itself is two degrees. **A positive
CLKOUTx_PHASE delays the output**, which is the convention the
library documents from the GW5A, so the backend passes the phase
through with its sign unchanged.
