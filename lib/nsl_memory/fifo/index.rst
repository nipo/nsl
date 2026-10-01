=====
FIFOs
=====

Choosing a fifo
===============

`fifo_auto`_ is the fifo new code should instantiate. It takes a
configuration record built by ``fifo_config()`` stating data width,
depth, clock count and the optional features needed (slices, fill
counters, cancellation), and picks the cheapest implementation that
provides them at elaboration, depending on the LUT RAM the target has
(see ``nsl_hwconfig.memory_config``).  Features that are not requested
cost nothing.

Selection rules, first matching one wins:

1. at most 2 words, without fill counters nor cancellation: a register
   slice, `fifo_register_slice`_ with one clock, followed by
   ``nsl_clocking.interdomain.interdomain_fifo_slice`` with two. Its
   ports are registered already, requested slices add nothing;

2. two clocks, fill counters or cancellation on either side:
   `fifo_homogeneous`_, which is the only one to have them. These need
   more than 2 words;

3. at most 16 words holding at most 16 bits in total (64 bits on a
   target without LUT RAM): `fifo_shift_register`_;

4. a target with asynchronous-read LUT RAM, and a depth up to the
   deepest fifo that is cheaper in LUT RAM than in block RAM on that
   target: `fifo_lutram`_;

5. otherwise `fifo_homogeneous`_, over block RAM.

Register slices go around the selected shift register or LUT RAM
block when requested. The rules
are available as ``fifo_auto_implementation()`` for code or tests that
need to know the outcome.

All implementations deliver words in order, without loss or
duplication, and hold at least the requested word count.  Latency and
cycle-level handshake timing differ between implementations, hence
between targets: a design must only rely on the ready/valid handshake.

.. _fifo_auto:

.. vhdl:autocomponent:: nsl_memory.fifo.fifo_auto

Generic fifo component
======================

The general-purpose fifo of NSL is `fifo_homogeneous`_. It may have
one or two ports depending on the `clock_count_c`` generic.  Data
width is homogeneous between input and output ports.  Optionally, one
may add a fifo slice at input and/or output port. It needs more than
2 words: a register slice is the fifo for one or two.

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

LUT RAM fifo
============

`fifo_lutram`_ is a single-clock fifo whose storage is an array written
synchronously and read asynchronously, which synthesizers map to LUT
RAM (Gowin SSRAM, Xilinx distributed RAM, Lattice DPR16X4) without any
attribute.  On a target without LUT RAM, the array becomes registers
and a read multiplexer.  Its port contract is the one of
`fifo_shift_register`_, cycle for cycle, and it takes any depth.  Its
output data goes through the LUT RAM read path rather than straight
out of a register.

.. _fifo_lutram:

.. vhdl:autocomponent:: nsl_memory.fifo.fifo_lutram

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
