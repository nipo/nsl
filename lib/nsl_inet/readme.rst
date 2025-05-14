================
 Network stack
================

Network stack uses `bnoc committed <../nsl_bnoc/committed>`_ bus
framework as a transport. It allows for late cancellation of frame, in
order to be able to do worm-hole handling of packets with optional
late-cancellation.

Multiple layers are implemented:

* All MII-related interfaces are in `nsl_mii <../nsl_mii>`_ library.

* `Ethernet <ethernet>`_ layer takes packet from MII to handle FCS and
  ethertype.

* `IPv4 <ipv4>`_ and `ARP <arp>`_ come above ethernet.

* `UDP <udp>`_ can be stacked over IP.

* `Checksum <checksum>`_ calculation module implements inet suite
  checksum. It can help to implement all protocols relying on it.

* `Testing framework <testing>`_ can craft packet for test-benches.

Unimplemented protocols can be plugged in at all the layers, any
ethertype may be used above Ethernet layer, any protocol may be
handled in IP packets, etc.
