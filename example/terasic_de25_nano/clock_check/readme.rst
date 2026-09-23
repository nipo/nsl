=========================
DE25-Nano clock bench
=========================

Measures, against the board's 50 MHz oscillator, what a bitstream
alone cannot say on an Agilex 5:

- the two outputs of an I/O PLL built by ``nsl_clocking.pll``, asked
  for at 100 and 125 MHz;
- the SDM's internal oscillator behind ``nsl_clocking.oscillator``,
  whose rate the data sheet does not state;
- a header pin driven by ``nsl_io.ddr.ddr_output`` with the halves of
  a forwarded clock, read back through its own input buffer.

The transport rides the part's JTAG and the measurer the oscillator,
so nothing measured here carries the link.  The oscillator is
``CLOCK0_50`` rather than the ``CLOCK1_50`` the JTAG bench uses:
``CLOCK1_50`` and the header pin share their way into the core, and
the fitter cannot route both as clocks.

``GPIO0_D0`` on the GPIO0 header carries the DDR output and must be
left unconnected.

Building
========

::

  gbs -C example/terasic_de25_nano/clock_check project build

1565 ALMs of 46800.  The fitter builds the PLL with N = 1, M = 60 and a
3000 MHz VCO, the mapping the solver states.  Every clock closes;
the tightest is the oscillator's, with 0.57 ns of setup slack at
20 ns, on crossings from the PLL outputs it shares a group with.

Measuring
=========

::

  acrobe chip -r ub3-/jtag/chain/0 program clock_check.rbf
  PYTHONPATH=$HOME/projects/gatecap/host acrobe run rates.py

::

  rack fingerprint 0x023b2042
  locked 1
  running:
    pll0        100000000 Hz, asked   100000000 Hz  ok
    pll1        125000000 Hz, asked   125000000 Hz  ok
    loopback    100000000 Hz, asked   100000000 Hz  ok
    internal    250000000 Hz
  still:
    loopback            0 Hz  ok

The internal oscillator reads exactly 250 MHz, twice the 125 MHz
``OSC_CLK_1`` this board configures from, rather than the loose
rate of a free-running oscillator.
