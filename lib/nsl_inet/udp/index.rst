=====
 UDP
=====

UDP layer-4 implementation, meant to be stacked on IPv4.

* a `receiver <udp_receiver.vhd>`_, exposing remote and local ports
  to layer 5;

* a `transmitter <udp_transmitter.vhd>`_, crafting the UDP header
  from the layer-5 context;

* a `layer <udp_layer.vhd>`_, bundling both with one bidirectional
  pipe per declared local port.  On these pipes the local port is
  implied by the pipe index, only the remote port travels in the
  header.

The UDP checksum is not computed on the datapath here; on transmit it
is filled in by the `ipv4 checksum inserter <../ipv4/index>`_.

``udp_pack()`` and the field getter functions allow crafting and
inspecting datagrams in testbenches.

Frame structures at the layer boundaries are documented in
`udp.pkg.vhd <udp.pkg.vhd>`_.
