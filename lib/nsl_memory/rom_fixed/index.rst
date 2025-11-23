
===============
Fixed-point ROM
===============

* `rom_ufixed <rom_ufixed.vhd>`_ is a single-port ROM containing
  ufixed values.  Actual ufixed precision depends on the signal range
  connected to `value_o`.  Initialization vector is a set of `real`
  values.  Conversion to ufixed constants is performed at elaboration
  time.

* `rom_sfixed <rom_sfixed.vhd>`_ is the same as previous with sfixed
  data type.

* `rom_ufixed_2p <rom_ufixed_2p.vhd>`_ is a dual-port ROM containing
  ufixed values.  Both ports read from the same backing storage.
  Backing storage is tailored to fit port A, but port B values will
  be resized to match B output value range.

* `rom_sfixed_2p <rom_sfixed_2p.vhd>`_ is the same as previous with
  sfixed data type.

Having dual-port ROMs of fixed-point data types can typically help
storing values for algorithms that need parallel lookup of two indices
of the table simultaneously.  A sinus/cosinus lookup table is an
example of such thing. See `trigonometry <../../nsl_signal_generator/trigonometry>`_
for usage example.
