=====================
 PS7 AXI ports check
=====================

Goal
====

Check `nsl_xilinx.ps7.ps7_wrapper` AXI ports on silicon, without any
software running on the PS:

* ``M_AXI_GP1`` with a non-native configuration, through an AXI to APB
  bridge, to a small register map;
* ``S_AXI_HP0`` in 32-bit mode, ``S_AXI_HP1`` in 64-bit mode and
  ``S_AXI_ACP``, each driven by a
  `nsl_amba.mm_traffic.axi4_mm_memory_tester` walking 64 kB of
  on-chip memory: HP0 at 0x00000, HP1 at 0x10000, ACP at 0x20000;
* ``S_AXI_GP0`` looped back to ``M_AXI_GP0``: a memory tester walks
  the 4 kB RAM the PL puts behind ``M_AXI_GP0``, at 0x40000000.

The register map sits on ``M_AXI_GP1`` rather than ``M_AXI_GP0``
because the memory tester base address is a ``natural``, which cannot
reach the ``M_AXI_GP1`` window at 0x80000000.

All ports run from the 125 MHz board clock.

Running
=======

With the boot mode jumper on JTAG, load the bitstream, then run the
check script over the same chain::

  acrobe chip -r <adapter>/jtag/chain program ps7_axi_check.bit
  python3.13 check.py <adapter>/jtag/chain

The script works through the DAP AHB-AP.  It unlocks SLCR, enables
the level shifters, releases PL resets, sets the AFI 32-bit mode of
HP0 and clears it on HP1.  Then it starts all testers through the
register map, and compares memory contents against the pattern the
testers write.

AFI registers are clocked by their port clock.  Accessing them while
the PL is not loaded hangs the AHB-AP until the board is power cycled.

Register map
============

At 0x80000000, 32-bit words, port ``i`` being 0 for HP0, 1 for HP1, 2
for ACP and 3 for the GP loopback:

* 0: control, tester enable (reset release) at bit ``i``, start at bit
  ``8+i``,
* 1: status, busy at bit ``2*i``, done at bit ``2*i+1``,
* ``2+3*i``: error count,
* ``3+3*i``: first error address,
* ``4+3*i``: clock cycles the tester was busy.
