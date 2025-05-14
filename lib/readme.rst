================
 VHDL libraries
================

Clocking
--------

`Clocking <nsl_clocking/>`_ contains some comprehensive clock-related
operations like:

* `Sampling asynchronous data <nsl_clocking/async>`_,

* `Clock-domain crossing <nsl_clocking/interdomain>`_,

* `Intra-domain operations <nsl_clocking/intradomain>`_,

* `Clock distribution buffers <nsl_clocking/distribution>`_,

* `Abstract PLL <nsl_clocking/pll>`_ instantiation (one input / one
  output) with automatic parameter calculation.

All these blocks come with proper timing constraints applied
automatically to get the intended behavior.

I/O
---

`Io <nsl_io/>`_ library is mostly constituted of packages defining
explicit record datatypes of various IO modes (opendrain, directed,
tri-stated, differential).  It also features usual IO blocks like `DDR
<nsl_io/ddr>`_, some basic serdes `(10 bit) <nsl_io/serdes>`_, `IO
delays <nsl_io/delay>`_.

Hardware-dependent
------------------

Even if most models try to use inference and refrains using
vendor-specific libraries, some parts are still vendor-specific.
Hardware-dependant library contains:

* Access to internal `built-in oscillators <nsl_hwdep/clock>`_ of
  FPGAs,
  
* Access to internal `built-in reset <nsl_hwdep/reset>`_ of FPGAs,

* Access to User-defined DRs of FPGAs `JTAG TAPs <nsl_hwdep/jtag>`_.

NSL tries to model common abstract components above these.

Generic utilities
-----------------

`Math utilities <nsl_math/>`_:

* General `arithmetic <nsl_math/arith/>`_ helpers,
* `Fixed-point <nsl_math/fixed/>`_ type and operators.

`Data manipulation <nsl_data/>`_ libary:

* `Bytestream manipulation <nsl_data/bytestream/>`_ byte-based
  generic types: byte_string (vector of bytes), byte_stream
  (dynamically allocated byte_string),

* `PRBS <nsl_data/prbs/>`_ generation framework,

* `CRC <nsl_data/crc/>`_ calculation and checking framework,

* `Endianness <nsl_data/endian/>`_ management and conversion
  functions.

Memory building blocks
----------------------

Memory blocks are all in `relevant library <nsl_memory/>`_

* `RAMs <nsl_memory/ram/>`_ (One port, two ports, two ports with different aspect ratios),

* `ROMs <nsl_memory/rom/>`_ (One port, two ports, specialized to hold
  fixed point constants),

* `FIFOs <nsl_memory/fifo/>`_,

* `LIFOs <nsl_memory/lifo/>`_,

* `Look-up tables <nsl_memory/lut/>`_.

Industry standard buses
-----------------------

Industry standard buses are usually quite flexible in their
configuration. NSL abstracts the details and gives the opportunity to
have generic implementation for a given protocol.

* `AMBA <nsl_amba/>`_ family of protocols:

  * `AXI4-MM <nsl_amba/axi4_stream/>`_ (lite and full featured),

  * `AXI4-Stream <nsl_amba/axi4_stream/>`_,

  * `APB <nsl_amba/apb/>`_ (version 2 to 4).

* `Wishbone <nsl_wishbone/>`_.

Custom On-chip communication framework
--------------------------------------

`Bnoc <nsl_bnoc/>`_ is a set of 8-bit wide data streaming
infrastructure models, with various features depending on the needs.

Serial protocol adapters
------------------------

* `JTAG <nsl_jtag/>`_, `SWD <nsl_coresight/swd/>`_, `I2C <nsl_i2c/>`_,
  `SPI <nsl_spi/>`_, `ChipCon <nsl_cc/>`_ debug protocol, `WS2812
  <nsl_ws/>`_, `UART <nsl_uart/>`_, `SMI <nsl_smi/>`_ (MDIO).

* I2C chip drivers for abstract usage

  * GPIO extender transactors (`PCA8574 <nsl_i2c/pca8574>`_, `PCA9534A
    <nsl_i2c/pca9534a>`_, `PCA9555 <nsl_i2c/pca9555>`_, `PCAL6524 <nsl_i2c/pcal6524>`_),

  * PLL initializer (`SI5351 <nsl_silabs/si5351>`_),

  * ADC drivers (`PCT2075 <nsl_i2c/pct2075>`_),

  * DAC drivers (`MCP4726 <nsl_i2c/mcp4726>`_),

  * LED drivers (`IS31FL3731 <nsl_i2c/is31fl3731>`_).

Fast IO protocols
-----------------

* `MII/RMII/GMII <nsl_mii/>`_ to Fifo bridges,

* `FT245 <nsl_ftdi/>`_ Synchronous Fifo interface transactor,

* `IBM 8b/10b <nsl_line_coding/ibm_8b10b/>`_, `DVI TMDS 8b/10b <nsl_dvi/encoder>`_,

* `10b serdeses <nsl_io/serdes/>`_ with automatic realignment.

High level communication stacks
-------------------------------

* `USB2 <nsl_usb/>`_ Full-speed/High-speed pure logic device,

* `Ethernet/IPv4/UDP <nsl_inet/>`_ stack.

Multimedia interfaces
---------------------

`DVI <nsl_dvi/>`_ and `HDMI <nsl_hdmi/>`_ transmitters, including HDMI
Data Island encapsulation (audio transport and other metadata).
Allows flexible and arbitrary image format generation.

`SPDIF <nsl_spdif/>`_ and `I2S <nsl_i2s/>`_ input/output, including
flexible clock source, clock recovery.

User-interface infrastructure
-----------------------------

* Led management, `color <nsl_color/>`_ abstraction, `PWM LED drivers
  <nsl_indication/rgb_led>`_, `WS2812 drivers <nsl_ws/driver>`_,
  `RGB24 and RGB8 <nsl_color/rgb/>`_ abstractions.

* Input button debouncers.

* `Rotary/linear encoder <nsl_sensor/quadrature/>`_ input frameworks.

Simulation helpers library
--------------------------

Simulation library contains either helpers for test-benches:

* feeding a fifo from a file,

* comparing fifo contents with a file,

  * driving reset and clocks in a test-bench context.
