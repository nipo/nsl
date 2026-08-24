==========
 Ethernet
==========

Ethernet MAC layer (layer 2).  Handles addressing, FCS and ethertype
dispatch.  Local unicast and broadcast destination addresses are
accepted; multicast is not supported.

Components:

* a `receiver <ethernet_receiver.vhd>`_, checking FCS and destination
  address, dropping frames with unhandled ethertypes, and exposing
  the index of the matched ethertype alongside the frame;

* a `transmitter <ethernet_transmitter.vhd>`_, crafting the MAC
  header, padding frames to a minimal size and appending FCS;

* a `layer <ethernet_layer.vhd>`_, union of the two above with one
  bidirectional frame pipe per declared ethertype;

* a `router <ethernet_router.vhd>`_, dispatching frames to one of
  several output ports based on a destination address lookup
  performed by an external resolver.

The package also defines the ``mac48_t`` address type, well-known
ethertype constants, the FCS CRC parameters, and frame
packing/inspection functions (``frame_pack()``,
``frame_daddr_get()``, etc.) usable in testbenches.

Frame structures at the layer boundaries are documented in
`ethernet.pkg.vhd <ethernet.pkg.vhd>`_.
