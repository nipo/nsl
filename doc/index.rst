============================
Native Synthesizable Library
============================

Purpose
=======

This project is a framework for portable HDL code that can be reused
across products and chip vendors.

Code source tree is used as a single library of source code. It has
various purposes:

* A build system able to compile a design either to a bitstream or a
  packaged IP for a given vendor toolsuite.

* A VHDL library of synthesizable components with portability kept in
  mind.

Moreover, this library contains various test benches for the
components.

Supported build toolsuites
==========================

This library build system targets major vendor's tool suites among
which:

* Vivado (Synthesis/PNR/Bitstream, IP-Xact Packaging),

* ISE (Synthesis/PNR/Bitstream), ISIM (simulation),

* GHDL (simulation),

* Lattice Diamond and IceCube (Synthesis/PNR/Bitstream),

* nvc (simulation, experimental).

Component scope
===============

This library started off as a support library for debugging probe
project, therefore, there is everything needed to build such project.
This is not limitative.

Components currently available in the HDL library include:

* Backend / target specific blocks:

  * Internal Clock generation components (FPGA startup clock blocks),

  * Internal Reset pulse generation components,

  * JTAG chain design-specific registers (DRs reserved for user in
    FPGA's TAP),

  * Pad/IO cell abstraction.

* The usual Low-level primitives:

  * Synchronization primitives (cross-clock-domain tools,
    resynchronization, etc),

  * RAMs (1 port, 2 ports, TDP),

  * FIFOs (sync, async).

* Communication networks:

  * AXI4-Lite, AXI4-Stream, message-queue,

  * Message routers.

* Bi-directional FIFO Communication bridges:

  * FT245-sync-fifo to fifo bridge,

  * FTDI "synchronous serial" to fifo bridge,

  * (R)MII to fifo bridge,

  * SPI slave to fifo bridge,

  * JTAG register to fifo bridge,

  * UART to fifo bridge.

* Utilities for a test-bench framework.

* Debugger bus masters:

  * JTAG,
  * SWD,
  * I2C,
  * SPI,
  * Ti's CC2xxx debugging protocol,
  * UART,
  * WS2812,
  * GPIO.