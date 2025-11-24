================================
 Asynchronous clocking utilites
================================

When signal enters the design from a foreign asynchronous domain, we
need to take some care in handling of signal.

:vhdl:component:`async_edge <nsl_clocking.async.async_edge>` is
typically used for reset signal sampling. Internally, it has a
cascaded pipeline of registers where output is released only once all
of them agree on the release of reset.
