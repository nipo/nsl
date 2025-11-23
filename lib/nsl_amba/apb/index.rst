
APB
===

All APB related declarations are scoped in the ``nsl_amba.apb`` package.

Configuration
-------------

Package supports from APB2 to APB4 (newer version is a superset of the
older).

Configuration for APB is held in ``config_t`` record type. It holds the
follwing settings:

* Address, data, *user,
* prot, rme, strb, ready, err and wakeup fields availability.

``config()`` function can generate such a configuration yet ensuring it
makes sense. ``apb2_config()``, ``apb3_config()`` and ``apb4_config()``
yield valid configurations for the matching subset of the
specification.

A ``version()`` call is able to tell which version of the spec the
configuration matches.

Example:

.. code:: vhdl

   constant config_c : config_t := config(address_width => 32,
                                          data_bus_width => 32);
   log_info("This is APB"&to_string(version(config_c)));

Signals
-------

Signals are split in the following records:

* Master-driven (``master_t``),
* Slave-driven (``slave_t``).

Like AXI signals, there are ``transfer_idle()``, ``write_transfer()``
and ``read_transfer()`` to generate master signal record.
``response_idle()``, ``write_response()`` and ``read_response()`` can
generate response slave signals.

Simulation helpers
------------------

``apb_write()``, ``apb_read()`` and ``apb_check()`` allow to drive apb
signals from a test bench for a minimal coding effort.  See
``tests/amba/apb_*`` for examples.

Function isolation
------------------

There are two entities available for abstracting basic bus
interfaces.

* ``nsl_amba.apb.apb_lite_slave`` is an entity taking care of the APB
  protocol details and gives an uniform synchronous interface to
  backend access in terms of read and write channel, non concurrent.

* ``nsl_amba.apb.apb_lite_regmap`` is abstracting even more as it:

  * Allows for a limited address space,
  * Limits to a set of full data width registers,
  * Only uses combinatorial reads.

  This is mostly useful for small register maps.

These two modules have exactly the same internal interface as the
AXI4-MM ones. They allow to implement basic memory-mapped function
blocks that are mildly tied to a given bus interface.
