=======================
 On-chip interconnects
=======================

.. toctree::

   nsl_amba/index
   nsl_wishbone/index
   nsl_bnoc/index

Industry Standards
------------------

Multiple industry standards are implemented in NSL.

NSL abstracts the details and gives the opportunity to have generic
implementation for a given protocol, including elaboration-time
reconfiguration of vector widths, sideband signals.

Industry standard buses are usually quite flexible in their
configuration.

* `AMBA <nsl_amba/index>`_ family of protocols:

  * `AXI4-MM <nsl_amba/axi4_mm/index>`_ (lite and full featured),

  * `AXI4-Stream <nsl_amba/axi4_stream/index>`_,

  * `APB <nsl_amba/apb/index>`_ (version 2 to 4).

* `Wishbone <nsl_wishbone/index>`_.

Custom On-chip Communication Framework
--------------------------------------

Before implementing high-end standard interconnects, NSL had the need
for an efficient communication framework. `bnoc`_ is a set of 8-bit
wide data streaming infrastructure models, with various features
depending on the needs.
