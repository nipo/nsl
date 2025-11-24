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

   design
   address/index
   axi4_mm/index
   axi4_stream/index
   apb/index
   apb_routing/index
   axi_apb/index
   mm_fifo/index
   ram/index
   stream_endpoint/index
   stream_fifo/index
