=====================
 PS8 AXI ports check
=====================

Goal
====

Check `nsl_xilinx.ps8.ps8_wrapper` AXI ports on a ZCU102, without any
software running on the PS:

* ``M_AXI_HPM0_LPD`` with a 32-bit configuration, through an AXI to
  APB bridge, to a small register map at 0x80000000;
* ``S_AXI_LPD`` in 128-bit mode, ``S_AXI_HPC0_FPD`` in 64-bit mode
  and ``S_AXI_HP0_FPD`` in 32-bit mode, each driven by a
  `nsl_amba.mm_traffic.axi4_mm_memory_tester` walking 64 kB of OCM:
  LPD at 0xFFFC0000, HPC0 at 0xFFFD0000, HP0 at 0xFFFE0000;
* ``S_AXI_HPC1_FPD`` looped back to ``M_AXI_HPM0_FPD`` (64-bit): a
  memory tester walks the 4 kB RAM the PL puts behind it, at
  0xA0000000.

Everything runs from PL clock 0, constrained at 100 MHz.  LEDs 0 to 3
light when the matching tester finished without error, LED 4 shows
the PL reset is released, LED 7 blinks while PL clock 0 runs.

Running
=======

With the boot mode switch on JTAG, load the bitstream, then run the
check script over the same chain::

  acrobe chip -r <adapter>/jtag/chain program ps8_axi_check.bit
  python check.py <adapter>/jtag/chain

The ARM DAP is only in the JTAG chain once the PS TAP ``JTAG_CTRL``
register (IR 0x824) is written with 0x3, even in JTAG boot mode.
acrobe does it when it finds the ZynqMP TAP.

The script works through the DAP AXI-AP.  It releases FPD, OCM, GPIO
and AFI resets, requests PL power-up from the PMU, starts PL clock 0
from IOPLL (at most 100 MHz), sets the AXI port data widths, then
pulses PL reset 0 (EMIO GPIO 95).  Then it starts all testers through
the register map, and compares memory contents against the pattern
the testers write.

Register map
============

At 0x80000000, 32-bit words, port ``i`` being 0 for S_AXI_LPD, 1 for
HPC0, 2 for HP0 and 3 for the HPC1 loop:

* 0: control, tester enable (reset release) at bit ``i``, start at bit
  ``8+i``,
* 1: status, busy at bit ``2*i``, done at bit ``2*i+1``,
* ``2+3*i``: error count,
* ``3+3*i``: first error address,
* ``4+3*i``: clock cycles the tester was busy.
