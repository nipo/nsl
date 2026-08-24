==========
 Ethernet
==========

Ethernet host adaptation — the addressing half of layer 2.  Stacked
on `mac <../mac/index>`_ (or on one branch of a VLAN demux), it
interprets what mac forwards transparently: destination address
filtering, compression of the wire addressing into a peer/context
header, and ethertype dispatch.  Local unicast and broadcast
destination addresses are accepted; multicast is not supported.

Components:

* a `receiver <ethernet_receiver.vhd>`_, filtering on destination
  address, dropping frames with unhandled ethertypes, and exposing
  the index of the matched ethertype alongside the frame;

* a `transmitter <ethernet_transmitter.vhd>`_, expanding the
  peer/context header back to destination/source addresses and
  inserting the ethertype;

* a `layer <ethernet_layer.vhd>`_, union of the two above with one
  bidirectional frame pipe per declared ethertype.

Frame structures at the layer boundaries are documented in
`ethernet.pkg.vhd <ethernet.pkg.vhd>`_.
