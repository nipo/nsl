====================
 Clocking utilities
====================

Clocking utilities are split by function:

* `asynchronous`_ when one of the domains is not clocked by the
  design, or not clocked at all,

* `interdomain`_ when signals are meant to cross a domain,

* `intradomain`_ when signals are meant to be kept in one domain,

* `distribution`_ for clock distribution cells such as global clock
  buffers,

* `pll`_ for simple PLL instantiation from various vendor backends.

Asynchronous
============

When signal enters the design from a foreign asynchronous domain, we
need to take some care in handling of signal.

:vhdl:component:`async_edge <nsl_clocking.async.async_edge>` is
typically used for reset signal sampling. Internally, it has a
cascaded pipeline of registers where output is released only once all
of them agree on the release of reset.
