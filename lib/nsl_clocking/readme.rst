====================
 Clocking utilities
====================

Clocking utilities are split by function:

* asynchronous_ when one of the domains is not clocked by the design,
  or not clocked at all,
* interdomain_ when signals are meant to cross a domain,
* intradomain_ when signals are meant to be kept in one domain,
* distribution_ for clock distribution cells such as global clock
  buffers,
* pll_ for simple PLL usage.

.. _asynchronous: asynchronous/
.. _interdomain: interdomain/
.. _intradomain: intradomain/
.. _distribution: distribution/
.. _pll: pll/

