
==========
BNOC Piped
==========

Pipe is the simplest abstraction level.  Fifo interface with one byte
per cycle, synchronous handshake.

From master to slave:

* data, an 8-bit value,

* valid.

From slave to master:

* ready, whether slave is ready to accept word from master.

This package provides a `fifo <pipe_fifo.vhd>`_.
