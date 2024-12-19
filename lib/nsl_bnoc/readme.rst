
============================================
 NSL-custom on-chip communication framework
============================================

Overview
========

`nsl_bnoc` is a set of 8-bit wide data streaming infrastructure
models, with variants features depending on the needs:

* `pipe <pipe/>`_, an unidirectional 8-bit fifo interface (typically
  used to interface a wire protocol transceiver, like an UART),

* `framed <framed/>`_, a `pipe <pipe/>`_ with added framing
  information (typically used to interface a wire protocol with
  framing info),

* `committed <committed/>`_, a `framed <framed/>`_ with late validity
  of packet (typically used to convey frames with a CRC check at the
  end),

* `routed <routed/>`_, a `framed <framed/>`_ with routing information
  header,

* converters, FIFOs, CRC checkers, router, buffers around these
  protocols.

Rationale
=========

As NSL started off as a project mainly focused on FPGA target, and the
primary target at the time was Spartan-6, 9-bit wide block RAMs were
the typical building block for FIFOs. Using 8-bit data + 1 bit `last`
was the best usage for FIFOs. Widening the data path to 16 or 32 bits
was first loosing 1 or 3 bits per word of storage, and then was
implying more costs in muxes and other infrastructure on the
arbitration points.

bnoc model still holds today on higher-end FPGAs to do basic control
infrastructure.
