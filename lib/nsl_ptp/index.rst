=====
 PTP
=====

IEEE 1588-2019 Precision Time Protocol:

* `ptp <ptp>`_: message definitions shared by the transport flavors;

* `stream_l2 <stream_l2>`_: ordinary clocks over ethernet (annex E)
  for the AXI4-Stream protocol suite, end-to-end delay mechanism,
  two-step.  Timestamps ride the `nsl_mii.timestamping
  <../nsl_mii/index>`_ sidebands; measurements feed the
  `nsl_time.discipline <../nsl_time/index>`_ servo.  Announce and
  the best master clock algorithm are not implemented: the slave
  locks on the first master it hears.
