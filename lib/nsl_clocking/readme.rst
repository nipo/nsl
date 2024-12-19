====================
 Clocking utilities
====================

Clocking utilities are split by function:

* `Asynchronous <asynchronous/>`_ when one of the domains is not
  clocked by the design, or not clocked at all,

* `Interdomain <interdomain/>`_ when signals are meant to cross a
  domain,

* `Intradomain <intradomain/>`_ when signals are meant to be kept in
  one domain,

* `Distribution <distribution/>`_ for clock distribution cells such as
  global clock buffers,

* `Pll <pll/>`_ for simple PLL instantiation from various vendor backends.

.. _asynchronous: asynchronous/
.. _interdomain: interdomain/
.. _intradomain: intradomain/
.. _distribution: distribution/
.. _pll: pll/

