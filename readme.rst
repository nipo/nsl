============================
Native Synthesizable Library
============================

NSL is a set of libraries of VHDL models, along with a build system
for various backend tools, either simulation or synthesis.

Libraries
=========

* Basic blocks:

  * Memories, FIFOs

  * Clock distribution, CDC utilities

  * IO types abstraction

  * Abstract DDR, serdes, delay blocks

* Generic data manipulation:

  * Byte/ByteString, endianness conversion

  * Abstract CRC computation, PRBS generation, Scramblers

* Interconnect models (including converter bridges):

  * AMBA AXI4-Stream and AXI4-MM, APB

  * Avalon-ST

  * Wishbone

* Serial protocols:

  * Debug protocols: JTAG, SWD, ChipCon

  * I2C, UART, SPI

* Video:

  * DVI output

  * HDMI output with DI encoding

  * Text screen renderer

* Audio:

  * I2S and SPDIF I/O

  * HDMI Audio DI encoding

* Line coding:

  * Machester

  * IBM 8b10b, TMDS 8b10b

* USB FS/HS device stack:

  * Descriptor serialization utilies

  * Arbitrary endpoint mapping and count

* Network device stack:

  * 802.3 RMII/MII/GMII/RGMII

  * Ethernet framing

  * IPv4/ARP/UDP

See `library root`_ for an overview of current libraries.

Portability
===========

NSL features backend-agnostic implementations and tries to limit
vendor-specific models to a bare minimum.

When vendor-specific models are necessary, NSL usually abstracts them
as blocks with a function-oriented common interface.  This creates a
gateware equivalent of a HAL.

Build-system selects the relevant implementation file depending on
target.

Main targets are, by decreasing maturity:

* Xilinx Series 6 and 7,

* Gowin Series 1, 2, 5,

* Altera Cyclone 10, Agilex 5

* Lattice Mach-XO2

* Lattice iCE40/ECP5 (through Yosys)

Build system
============

NSL supports two different build systems:

* Integrated Makefile-based build system,

* External Python-based GBS_, a gateware build system.

Both build systems rely on explicit enumeration of sources, split in
libraries and partition in libraries (usually matching packages).
Dependencies are selected per-partition in a way only a subset of a
whole library may be used for a design.

License
=======

NSL Uses the MIT license.

.. _library root: lib/
.. _GBS: https://github.com/nipo/gbs
