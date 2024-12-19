
AXI4-Stream fifos
=================

Fifo blocks come in three flavors:

* Full fifo with one or two clock domains,

* Fifo slice, a.k.a. a skid buffer.  All output signals are
  registered.  This allows to break combinatorial paths This actually
  is a 2-deep fifo where pipelining can happen.

* A clock-domain-crossing module. This one only handles one beat at a
  time. This is mostly useful for low bandwidth streams.
