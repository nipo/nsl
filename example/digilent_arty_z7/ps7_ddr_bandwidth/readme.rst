=====================
 PS7 DDR bandwidth
=====================

Goal
====

Measure the DDR bandwidth `nsl_xilinx.ps7.ps7_wrapper` HP ports give
to PL masters, directly and through `nsl_amba.mm_routing.axi4_mm_crossbar`.

Four `nsl_amba.mm_traffic.axi4_mm_memory_tester`, 64-bit, 16-beat
bursts, 8 transactions in flight, each walk 16 MB of DDR from
0x10000000 up:

* testers 0 and 1 share ``S_AXI_HP0`` through the crossbar, with
  register slices on both sides;
* testers 2 and 3 have ``S_AXI_HP1`` and ``S_AXI_HP2`` to themselves.

Everything runs from the 125 MHz board clock, so a port tops at
1000 MB/s in each direction.

Running
=======

The DDR controller must be initialized by boot software.  Boot from
the SD card, then halt both CPUs, load the bitstream, and run::

  python3.13 check.py <adapter>/jtag/chain halt
  acrobe chip -r <adapter>/jtag/chain program ps7_ddr_bandwidth.bit
  python3.13 check.py <adapter>/jtag/chain run

Halting first keeps boot software from accessing the PL while it is
reprogrammed.  "halt" also holds PL resets and disables PS-PL level
shifters: otherwise, PL outputs glitching during configuration can
leave an HP port with stray write data, hanging it until the PS is
reset.  The script halts cores through the debug APB-AP, then
does everything else through the AHB-AP.  It runs testers in several
combinations, and prints write and read bandwidth of each.  Testers
check every beat they read; the script also reads back a few samples.

When testers run concurrently, each one's rate is measured over its
own busy time.  Phases of different testers drift apart, so totals
are only meaningful while testers run at the same rate.

Register map
============

At 0x80000000, 32-bit words, ``i`` being the tester index:

* 0: control, tester enable (reset release) at bit ``i``, start at bit
  ``8+i``,
* 1: status, busy at bit ``2*i``, done at bit ``2*i+1``,
* ``2+4*i``: error count,
* ``3+4*i``: first error address,
* ``4+4*i``: clock cycles spent writing,
* ``5+4*i``: clock cycles spent reading.
