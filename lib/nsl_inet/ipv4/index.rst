======
 IPv4
======

IPv4 layer-3 implementation, together with ICMP, which IPv4 requires
to function.

* a `receiver <ipv4_receiver.vhd>`_, validating the IP header
  (including its checksum, inline), accepting local unicast and
  broadcast destinations (no multicast), and exposing peer address,
  address context, protocol and PDU size to layer 4;

* a `transmitter <ipv4_transmitter.vhd>`_, crafting the IP header
  from the layer-4 context;

* `icmpv4 <icmpv4.vhd>`_, an ICMP responder able to answer echo
  requests (ping);

* a `checksum inserter <ipv4_checksum_inserter.vhd>`_, meant to be
  inserted between the IP layer and the layer below on the transmit
  path.  It computes IP/ICMP/UDP/TCP checksums while the packet
  traverses a fifo and rewrites the header fields on the way out,
  keeping delay minimal.  IP and ICMP handling are always on, UDP
  and TCP are optional;

* a `layer <ipv4_layer.vhd>`_, bundling receiver, transmitter, ICMP,
  checksum inserter and a protocol dispatcher with one bidirectional
  pipe per declared IP protocol.

Fragmentation is not handled: fragmented packets are classified as
invalid.

The package also provides packet packing/inspection functions
(``ipv4_pack()``, ``icmpv4_pack()``, field getters) for testbenches,
and IP header offset constants.

Frame structures at the layer boundaries are documented in
`ipv4.pkg.vhd <ipv4.pkg.vhd>`_.
