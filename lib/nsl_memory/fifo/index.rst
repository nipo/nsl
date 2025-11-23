
=====
FIFOs
=====

Components
==========

* Only one model of fifo exists in NSL: `fifo_homogeneous
  <fifo_homogeneous.vhd>`_. It may have one or two ports depending on
  the `clock_count_c` generic.  Data width is homogeneous between
  input and output ports.  Optionally, one may add a fifo slice at
  input and/or output port.

  Fifo counters giving count of free positions (on write side) and
  available words (on read side) are available.  These counters are
  pessimistic in the sense they never give an overestimate of the actual
  numbers.

* A register slice `fifo_register_slice <fifo_register_slice.vhd>`_ is
  also known as a skid buffer.  It has fifo semantics but all its
  outputs come from a register. This actually eases timing closure
  where modules have long combinatorial paths at the boundaries.  It
  is actually implemented as a 2-deep fifo using registers.

* `fifo_widener <fifo_widener.vhd>`_ is a module with fifo semantics
  where the output port is an integer multiple width of the input
  port.
  
* `fifo_narrower <fifo_narrower.vhd>`_ is a module with fifo semantics
  where the input port is an integer multiple width of the out port.

* `fifo_cancellable <fifo_cancellable.vhd>`_ is a fifo where read and
  write pointers are updated on peer port only if a commit is
  performed. Instead, if a cancellation is requested by either input
  or output side, pointers from said side are reverted back to last
  commit state.  This can be used to implement retransmission buffers.
