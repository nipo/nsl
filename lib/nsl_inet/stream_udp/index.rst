============
 Stream UDP
============

UDP layer for the AXI4-Stream protocol suite, between the IPv4
layer's UDP pipe and the applications, one stream pair per entry of
the port table:

* ``stream_udp_receiver`` verifies the checksum when present
  (rejecting on the last beat, where the verdict lands), matches the
  datagram length against the IPv4 context, and dispatches on
  destination port.  The context block carries the peer port;

* ``stream_udp_transmitter`` crafts headers from the pipe's port
  table entry and the context, with a zero checksum, which IPv4
  permits;

* ``stream_udp_layer`` bundles both.

The layer is a sibling of `stream_ipv4 <../stream_ipv4/index>`_: the
last forwarded block must be the IPv4 context, read for the
pseudo-header and the datagram length, forwarded untouched.
