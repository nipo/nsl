
AXI4-MM fifos
=============

Fifo blocks come in three flavors, for each of the four streams
(Address, Write data, Read data and Write response):

* Full fifo with one or two clock domains,

* Fifo slice, a.k.a. a skid buffer.  All output signals are
  registered.  This allows to break combinatorial paths This actually
  is a 2-deep fifo where pipelining can happen.

* A clock-domain-crossing module. This one only handles one beat at a
  time. This is mostly useful for low bandwidth streams.

There is one bus fifo component `axi4_mm_fifo`, where fifo depth and
number of clocks (one or two) can be specified.  Depending on fifo
depth and number of clocks, component will automatically instantiate
any of the three blocks above.  Fifo depth can be independently set
for the 5 channels.
