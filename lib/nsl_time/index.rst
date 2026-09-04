===================
 Real-Time Library
===================

Real-Time library tracks actual time.  It is the root for precision
timing infrastructure (PTP, PPS, etc.).

In the library, there are:

* A `timestamp <timestamp>`_ package that conveys the current time
  down to the nanosecond resolution,

* A `skew <skew>`_ package that allows to do timestamp operations,

* PPS interoperability, including `PPS generation <pps>`_ and `PPS extraction <clock>`_ blocks.

* A `calendar <calendar>`_ package converting a second count into
  date and time of day.

* A `capture <capture>`_ package sampling the current time into a
  small register file on frame timestamping sidebands (see
  `nsl_mii.timestamping <../nsl_mii/index>`_).

* A `discipline <discipline>`_ package steering the local clock from
  offset measurements: a PI servo turning the
  `skew <skew>`_-currency measurement stream into a frequency
  correction, and drivers applying it to `clock <clock>`_'s
  adjustable increment or to a DAC pulling a VCTCXO.  Sources (PTP,
  PPS, custom protocols) and sinks stay interchangeable.
