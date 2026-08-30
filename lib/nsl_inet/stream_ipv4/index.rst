=============
 Stream IPv4
=============

IPv4 layer for the AXI4-Stream protocol suite, between the ethernet
layer's 0x0800 pipe and the layer-4 protocols:

* ``stream_ipv4_receiver`` validates the header (checksum, no
  options, no fragment), filters on destination address (local
  station or limited broadcast), trims the PDU to the declared
  length, and dispatches on protocol, one stream pair per entry of
  the protocol table.  The context block carries peer address,
  casting and PDU length;

* ``stream_ipv4_transmitter`` crafts headers from the context, the
  protocol coming from the input pipe's table entry, checksum
  computed at crafting time;

* ``stream_ipv4_layer`` bundles both;

* ``stream_ipv4_icmp_echo`` answers echo requests cut-through on the
  ICMP pipe, cancelling replies to corrupted requests through the
  reject flag.
