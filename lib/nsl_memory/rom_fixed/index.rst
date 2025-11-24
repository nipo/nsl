===============
Fixed-point ROM
===============

`rom_ufixed`_ is a single-port ROM containing
ufixed values.  Actual ufixed precision depends on the signal range
connected to `value_o`.  Initialization vector is a set of `real`
values.  Conversion to ufixed constants is performed at elaboration
time.

.. _rom_ufixed:

.. vhdl:autocomponent:: nsl_memory.rom_fixed.rom_ufixed

`rom_sfixed`_ is the same as previous with sfixed
data type.

.. _rom_sfixed:

.. vhdl:autocomponent:: nsl_memory.rom_fixed.rom_sfixed

`rom_ufixed_2p`_ is a dual-port ROM containing
ufixed values.  Both ports read from the same backing storage.
Backing storage is tailored to fit port A, but port B values will
be resized to match B output value range.

.. _rom_ufixed_2p:

.. vhdl:autocomponent:: nsl_memory.rom_fixed.rom_ufixed_2p

`rom_sfixed_2p`_ is the same as previous with
sfixed data type.

.. _rom_sfixed_2p:

.. vhdl:autocomponent:: nsl_memory.rom_fixed.rom_sfixed_2p

Having dual-port ROMs of fixed-point data types can typically help
storing values for algorithms that need parallel lookup of two indices
of the table simultaneously.  A sinus/cosinus lookup table is an
example of such thing. See `trigonometry <../../nsl_signal_generator/trigonometry>`_
for usage example.
