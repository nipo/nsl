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
