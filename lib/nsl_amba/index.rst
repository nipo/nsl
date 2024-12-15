==============================
 AMBA Communication framework
==============================

Supported interfaces
====================

AMBA is a set of on-chip protocols. NSL chose a subset, among which:

* AXI4-MM, used to model a generic memory bus infrastructure. It is
  flexible in terms of address and data width, has support for
  optional bursts, various platform-specific side-band signaling, etc.

  A minimal subset of AXI4-MM is called AXI4-Lite.

* AXI4-Stream, used to model streams of data. It is flexible in terms
  of data width, sideband data, routing information. Even backpressure
  is optional.

* APB, used to access low-performance register maps, mostly used for
  low-bandwidth peripherals.

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

.. toctree::

   axi4_mm
   axi4_stream
   apb

