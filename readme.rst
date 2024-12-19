============================
Native Synthesizable Library
============================

NSL is a set of libraries of VHDL models, along with a build system
for various backend tools, either simulation or synthesis.

NSL tries hard to have backend-agnostic implementation and to limit
vendor-specific models to a bare minimum.

Project started as a library for building debug probes (JTAG, SWD), so
it has a strong bias towards serial protocols.  Over time, it
diversified to other fields.

See `library doc root`_ for an overview of current libraries.

License
=======

NSL Uses the MIT license.

.. _library doc root: lib/
