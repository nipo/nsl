====================
 Clocking utilities
====================

Clocking utilities are split by function:

* `asynchronous <async/index>`_ when one of the domains is not
  clocked by the design, or not clocked at all,

* `interdomain <interdomain/index>`_ when signals are meant to cross a domain,

* `intradomain <ntradomain/index>`_ when signals are meant to be kept in one domain,

* `distribution <istribution/index>`_ for clock distribution cells such as global clock
  buffers,

* `pll <oll/index>`_ for simple PLL instantiation from various vendor backends.

.. toctree::

   async/index
   interdomain/index
   intradomain/index
   distribution/index
   pll/index
