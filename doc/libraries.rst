================
 VHDL libraries
================

Clocking
--------

`lib/nsl_clocking/` contains some comprehensive clock-related
operations like:

* Sampling asynchronous data,
* Crossing clock domains,
* Intra-domain operations,
* Clock distribution buffers,
* Simple PLL instantiation tempaltes (one input / one output)s.

All these blocks come with generic constraints that apply the intended
behavior for most supported tools.

Math and bit manipulation
-------------------------

`lib/nsl_math` contains some basic arithmetic primitives, but also
gray encoder/decoder, some basic logic routines and fixed point datatype.

I/O
---

IO library is mostly constituted of packages defining explicit record
datatypes of various IO modes (opendrain, directed, tri-stated,
differential).  It also features usual IO blocks like DDR, some basic
serdes (10 bit), IO delays.

Hardware-dependant
------------------

Even if most models try to use inference and refrains using
vendor-specific libraries, some parts are still vendor-specific.
Hardware-dependant library contains:

* Access to internal built-in oscillators of FPGAs,
* Access to internal built-in reset of FPGAs,
* Access to User-defined DRs of FPGAs JTAG TAPs.

On-chip communication framework
-------------------------------

`lib/nsl_bnoc` features many communication infrastructures, including:

* pipe, an unidirectional 8-bit fifo interface,
* framed, pipe with added end of frame information,
* committed, framed with late cancellation of packet,
* routed, framed with routing information,
* converters, fifos, buffers around these protocols.

Various serial protocol adapters
--------------------------------

* JTAG, SWD, I2C, SPI, ChipCon debug protocol, WS2812, UART,
  SMI (MDIO), SPDIF, I2S.

Fast IO protocols
-----------------

* MII/RMII to Fifo bridges,
* FT245 Synchronous Fifo interface transactor,
* 8b/10b implementation, 10b serdeses with automatic realignment.

High level communication stacks
-------------------------------

* USB2 Full/High-speed Device implementation,
* Ethernet/IPv4/UDP implementation.

Simulation helpers library
--------------------------

Simulation library contains either helpers for test-benches:

* feeding a fifo from a file,
* comparing fifo contents with a file,
* driving reset and clocks in a test-bench context.

