=====
FIFOs
=====

Generic fifo component
======================

The general-purpose fifo of NSL is `fifo_homogeneous`_. It may have
one or two ports depending on the `clock_count_c`` generic.  Data
width is homogeneous between input and output ports.  Optionally, one
may add a fifo slice at input and/or output port.

Fifo counters giving count of free positions (on write side) and
available words (on read side) are available.  These counters are
pessimistic in the sense they never give an overestimate of the actual
numbers.

.. _fifo_homogeneous:

.. vhdl:autocomponent:: nsl_memory.fifo.fifo_homogeneous

Register slice
==============

A register slice `fifo_register_slice`_ is
also known as a skid buffer.  It has fifo semantics but all its
outputs come from a register. This actually eases timing closure where
modules have long combinatorial paths at the boundaries.  It is
actually implemented as a 2-deep fifo using registers.

.. _fifo_register_slice:

.. vhdl:autocomponent:: nsl_memory.fifo.fifo_register_slice

Shallow fifo
============

`fifo_shift_register`_ is a fifo for depths of a few words, made of a shifting
chain of registers steered by a one-hot fill register.  It has neither
RAM nor fill counter, and its output data comes directly out of a
register.  Its fill level is exposed as the one-hot register itself,
so conditions such as "at least K words held" are single bit tests.

.. _fifo_shift_register:

.. vhdl:autocomponent:: nsl_memory.fifo.fifo_shift_register

Width conversion
================

`fifo_widener`_ and `fifo_narrower`_ are modules with fifo semantics
where the output port is an integer multiple width of the input port
(or the other way around).

.. _fifo_widener:

.. vhdl:autocomponent:: nsl_memory.fifo.fifo_widener

.. _fifo_narrower:

.. vhdl:autocomponent:: nsl_memory.fifo.fifo_narrower

Cancellable fifo
================

`fifo_cancellable`_ is a fifo where read and
write pointers are updated on peer port only if a commit is
performed. Instead, if a cancellation is requested by either input
or output side, pointers from said side are reverted back to last
commit state.  This can be used to implement retransmission buffers.

.. _fifo_cancellable:

.. vhdl:autocomponent:: nsl_memory.fifo.fifo_cancellable
