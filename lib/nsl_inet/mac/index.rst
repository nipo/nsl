=====
 MAC
=====

Ethernet MAC framing — the wire-conditioning half of layer 2, per
physical port.  This layer is transparent: destination and source
addresses and the ethertype are forwarded untouched, in-band.
Address interpretation, filtering and ethertype dispatch belong to
`ethernet <../ethernet/index>`_, stacked above.

* a `receiver <mac_receiver.vhd>`_, checking and stripping FCS;
  frames with a bad FCS are forwarded with the validity bit cleared;

* a `transmitter <mac_transmitter.vhd>`_, padding committed frames to
  the minimal frame size and appending FCS;

* a `router <mac_router.vhd>`_, dispatching frames to one of several
  output ports based on a destination address lookup performed by an
  external resolver.

Because nothing is filtered or rewritten here, this boundary is also
the one transparent forwarding devices build on: a VLAN fan-out
router is a set of per-port MAC layers around `vlan <../vlan/index>`_
demux/mux, with no host adaptation anywhere.

The package also defines the ``mac48_t`` address type, well-known
ethertype constants, the FCS CRC parameters, and frame
packing/inspection functions (``frame_pack()``,
``frame_daddr_get()``, etc.) usable in testbenches.

Frame structures at the layer boundaries are documented in
`mac.pkg.vhd <mac.pkg.vhd>`_.
