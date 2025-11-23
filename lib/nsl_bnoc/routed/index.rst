
===========
BNOC Routed
===========

Routed is a `framed <../framed/>`_ with first byte in the frame
conveying routind information.  4 LSBs are destination, 4 MSBs are
source.

This package provides various conversion tools:

* a `fifo <routed_fifo.vhd>`_, a `fifo slice <routed_fifo_slice.vhd>`_,

* a `router <routed_router.vhd>`_ where a routing table maps
  destination addresses to ports,

* `entry <routed_entry.vhd>`_ and `exit <routed_exit.vhd>`_ nodes to a
  framed network,

* an `endpoint <routed_endpoint.vhd>`_ where one received framed on
  the routing network is forwarded without the routing header.  One
  response frame is expected from the framed network and sent back to
  the source.
