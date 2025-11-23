==========
BNOC Piped
==========

Pipe is the simplest abstraction level.  Fifo interface with one byte
per cycle, synchronous handshake.

From master to slave, :vhdl:type:`pipe_req_t
<nsl_bnoc.pipe.pipe_req_t>` holds:

* data, an 8-bit value,

* valid.

From slave to master, :vhdl:type:`pipe_ack_t
<nsl_bnoc.pipe.pipe_ack_t>` holds:

* ready, whether slave is ready to accept word from master.

This package provides a :vhdl:component:`fifo <nsl_bnoc.pipe.pipe_fifo>`.
