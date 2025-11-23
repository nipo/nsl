
===========
BNOC Framed
===========

Framed is a stream of bytes with additional frame boundary.

From master to slave:

* data, an 8-bit value,

* valid,

* last, whether this word is the last one of a frame.

From slave to master:

* ready, whether slave is ready to accept word from master.

This package provides various conversion tools:

* a `fifo <framed_fifo.vhd>`_,

* a `fifo slice <framed_fifo_slice.vhd>`_,

* an `atomic fifo <framed_fifo_atomic.vhd>`_, i.e. a fifo that starts
  to output frame as soon as it has been totally received,

* Various arbitration and routing utilities:

  * a simple `gate <framed_gate.vhd>`_,

  * a command/response `gate <framed_granted_gate.vhd>`_,

  * an `arbitrer <framed_arbitrer.vhd>`_,

  * a `funnel <framed_funnel.vhd>`_ and a `dispatcher <framed_dispatch.vhd>`_,

  * a `crossbar <framed_matrix.vhd>`_,

  * converters from `pipe <../pipe/>`_, either with `explicit end
    <framed_committer.vhd>`_ or `on a timeout  <framed_framer.vhd>`_,

  * `converter to pipe <framed_unframer.vhd>`_,

  * `router <framed_router.vhd>`_ working on frame header.
