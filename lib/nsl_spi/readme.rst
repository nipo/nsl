=============================
 Serial Peripheral Interface
=============================

SPI library has:

* a basic SPI `shift register <shift_register>`_, either with external
  clocking or with oversampling of external SCK,

* `slave <slave>`_ implentations, clocked or not,

* `master <transactor>`_ implentations from a command/response stream,
  including a muxed model where chip-select is driven by a SPI-based
  shift register,

* a `SPI flash reader <flash>`_,

* utilities to `transport fifo streams <fifo_transport>`_ over SPI.

