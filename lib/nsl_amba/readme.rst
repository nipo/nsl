==============================
 AMBA Communication framework
==============================

Supported interfaces
====================

AMBA is a set of on-chip protocols. NSL chose a subset, among which:

* `AXI4-MM <axi4_mm/>`_, used to model a generic memory bus
  infrastructure. It is flexible in terms of address and data width,
  has support for optional bursts, various platform-specific side-band
  signaling, etc.

  A minimal subset of AXI4-MM is called AXI4-Lite.

* `AXI4-Stream <axi4_stream/>`_, used to model streams of data. It is
  flexible in terms of data width, sideband data, routing
  information. Even backpressure is optional.

* `APB <apb/>`_, used to access low-performance register maps, mostly
  used for low-bandwidth peripherals.

Genericity
==========

Genric coding pitfall
---------------------

As these protocols are quite flexible and change in configuration
imply changes in the way signals are interpreted, a baseline generic
implementation must check for configuration details every time it
dereferences a signal. Let's take a few examples:

* In AXI4-MM, awburst/arburst signal is optional. Still, when kept
  out, bursts are permitted if awlen/arlen field is available. Burst
  defaults to 0b01 (INCR) when absent.

* In AXI4-MM, if no burst is possible, wlast and rlast are kept out,
  they are useless. Every data burst is one-beat.

* In AXI4-Lite, if there is no TLAST, depending on the model, stream
  can be handled as one continuous or many one-beat transfers.

* In AXI4-Lite, TREADY may not be supported and implied to be true.

In all these examples, actually remembering to perform all the tests
on every access to the signals is error prone. NSL avoids all this by
abstracting the models.

Generic modelization concept
----------------------------

For all AMBA descendants, NSL keeps all the configuration and the bus
interface in a record.

Configuration record should typically be a constant in top-level
module, and be a generic in various compatible models.  This record
should be generated through call to some factory function with sane
defaults, verifying the configuration actually makes sense in terms of
specification constraints.

Signals are encapsulated in records. IO for a typical NSL AMBA model
is two records per bus, one for each direction.  For instance, for
AXI4-MM (lite or full featured), there is one
`nsl_amba.axi4_mm.master_t` and one `nsl_amba.axi4_mm.slave_t` record.
These records actually cover the worst-case usage in term of logic
signals.

In order not to dereference signals that are excluded by the
configuration, every access to these records should be performed
through functions, either for reading signals out of ports, or for
generating values set to these signals.

In a normal synthesis environment, constant, unused signals will be
optimized out. Moreover, proper constant propagation will also
optimize state machines and data types.  Still, code can be kept clean
and generic.


Available modules
=================

* `Generic address <address/>`_ handling,

* `AXI4-MM <axi4_mm/>`_

  * `dumper <axi4_mm/axi4_mm_dumper.vhd>`_ (for debug),

  * `AXI4-Lite slave <axi4_mm/axi4_mm_lite_slave.vhd>`_ helper,

  * `AXI4-Lite register map <axi4_mm/axi4_mm_lite_regmap.vhd>`_ helper,

  * `fifos, clock-domain crossing and register slices <mm_fifo/>`_,

  * `MM-over-Stream encapsulation framework <mm_stream_adapter/>`_
    (transports a full AXI-MM over a Stream interface),

  * `MM-Stream endpoint <stream_endpoint/>`_, a MM device that allows
    pushing to stream and reading from stream,

  * `RAMs <ram/>`_.

* `AXI4-Stream <axi4_stream/>`_

  * `dumper <axi4_stream/axi4_stream_dumper.vhd>`_ (for debug),

  * `width adapter <axi4_stream/axi4_stream_width_adapter.vhd>`_ to
    resize data vector of a stream,

  * `flusher <axi4_stream/axi4_stream_flusher.vhd>`_ to insert beats
    with a TLAST either after a max frame size of after a timeout,

  * `FIFOs <stream_fifo/>`_,

  * `Funnel and dispatcher <stream_routing/>`_.

* `APB <apb/>`_

  * `dumper <apb/apb_dumper.vhd>`_ (for debug),

  * `slave <apb/apb_slave.vhd>`_ helper,

  * `register map <apb/apb_regmap.vhd>`_ helper,

  * `RAM <ram/>`_.
