==============================
 AMBA Communication framework
==============================

Supported interfaces
====================

AMBA is a set of on-chip protocols. NSL chose a subset, among which:

* `AXI4-MM <axi4_mm/index>`_, used to model a generic memory bus
  infrastructure. It is flexible in terms of address and data width,
  has support for optional bursts, various platform-specific side-band
  signaling, etc.

  A minimal subset of AXI4-MM is called AXI4-Lite.

* `AXI4-Stream <axi4_stream/index>`_, used to model streams of data. It is
  flexible in terms of data width, sideband data, routing
  information. Even backpressure is optional.

* `APB <apb/index>`_, used to access low-performance register maps, mostly
  used for low-bandwidth peripherals.

Detailed description
====================

.. toctree::

   address
   axi4_mm
   axi4_stream
   apb
   design
