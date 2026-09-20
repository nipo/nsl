# DDR3 bring-up probe on the Tang Console 60k

Hand-driven pins against the SOM's H5TQ4G63EFR at DDR3-800, written to
find out what the part and the fabric's IO logic actually do rather
than to move data.  It is a bench, not a controller: every command is
placed by a state machine of its own, and what comes back leaves over
the UART and over a gatecap analyzer on the board's fabric USB port.

One fabric cycle at 100MHz spans four memory ticks.  Only chip select
and the two clock pins move faster than that: commands are masked
while chip select is high, so address and control sit still for a
whole cycle and a one-tick chip select pulse picks the tick that
carries the command.

## Building and running

    $ gbs project build
    $ programmer_cli --location <n> --device GW5AT-60B \
        --operation_index 2 -f gbs-build/ddr3_probe2.fs --frequency 15MHz

The report comes out of the UART at 115200 8N1: an eye per data lane,
a bit per delay tap, then a line saying where each lane was parked and
whether it reads cleanly there.

For the bus itself, over the USB2 data port:

    $ acrobe gatecap -r tty-<dev>/serial/chunked/gatecap \
        capture pins.control --trigger phase=0x3 --count 64 --pretrigger 8

The input serialisers hand the analyzer eight slots a cycle, so a
capture has slot resolution while the instrument runs at fabric rate.
The phase field says which part of the sequence a cycle belongs to and
is what triggers, so a capture pins itself to the write burst rather
than to whenever the host armed it.

A row of `diagnose_*` and `skip_*` constants at the top of
`src/boundary.vhd` cut the sequence down to one question at a time;
each carries a comment saying what its answer means.

## What it settled

**Which DDR3 site is populated.**  The SOM has two footprints sharing
every command pin and no silkscreen refdes.  Reading the multi purpose
register through both pin groups moves the first site's lanes and
leaves the second's still, so the first is fitted and the second is
empty -- confirmed against a run with the register left disabled,
where nothing moves at all.

**A serialiser and a plain register do not reach a pin together.**
Chip select through a serialiser arrives a couple of fabric cycles
after address and control through plain registers, so chip select was
strobing after the address bus had moved on and every command reached
the part as a no-op.  Commands have to stand for several cycles with
the pulse falling inside that window.

**A mode register write needs an idle part.**  Switching the multi
purpose register off was issued with a row still open, so the part
quietly stayed in the register: every later read answered from it, the
activate was illegal and ignored, and an array read landed nowhere.
This looked like a broken activate for a long time.  Precharge first.

**A serialiser needs its two clocks in a settled relationship.**  Data
on a three-quarter-shifted fast clock with the parallel clock divided
from the unshifted one made a serialiser hold a stale word for another
sixty five nanoseconds past its eight beats.  On one clock pair it
emits exactly eight beats and stops.  A strobe that needs its own
phase is better built from a double rate register, which takes one
clock and no parallel clock at all.

**The lanes do not arrive together.**  DQ0 lands about a sample later
than DQ8 -- some 762ps of skew -- so a judging window pinned to the
burst start sees no eye on DQ0 at all, and each lane needs its own
delay line and its own trained answer.  Measured eyes at DDR3-800 were
325ps and 675ps on DQ0, 1088ps and 938ps on DQ8.

**A pin's IO logic will not do two things at once.**  It will not take
an input serialiser on one clock beside an output register on another,
and it will not take two input serialisers.  Both are refused by the
tools rather than silently mis-built.

**A toggling strobe cannot be watched by the clock that clocks it.**
Delaying it on the way in does not fit -- those pins already carry an
output serialiser.  A second analyzer domain off a shifted clock would
read it, but the domain crossing costs a run-dependent skew, which is
the very quantity a strobe measurement is after.  Driving it at a
steady level answers the one question left, which is whether it is
driven at all.

**Write levelling works, and the strobe generator's step is 14.6ps.**
Walking WSTEP across its whole range while the part sits in its
levelling mode draws a square wave: the answer holds, turns, and turns
back, one memory clock period every hundred and seventy steps.  The
zero to one crossing -- the strobe rising with the clock -- lands at
step 151 on one lane and 150 on the other.  The generator needs a
delay locked loop of its own feeding its step; the tools refuse one
wired to anything else.

## What is still open

Reads work and the strobe is levelled.  **No write has landed**, and
none is expected to yet.

The two halves of a write are now half done.  The strobe rises with
the memory clock, which is what tDQSS asks.  The data is still
launched from the fabric clock, so a strobe that has moved onto the
clock is no longer centred in the data eye -- the same collision as
before, seen from the other side.

Closing it means launching the data from the generator's DQSW270,
which is a quarter of a bit ahead of the strobe, so that both hold at
once.  That takes the capture side with it: a pin will not carry an
input serialiser on one clock beside an output serialiser on another,
so the data lanes have to move to the memory input serialiser clocked
from DQSR90, with the read gate and its quarter-tick select that go
with it.  Lane by lane is not available; it is the whole data path or
none of it.

At that point this bench and `nsl_ext_ram.ddr3_io.ddr3_phy_gowin` are
the same thing, and the probe should instantiate the PHY rather than
grow its own copy.
