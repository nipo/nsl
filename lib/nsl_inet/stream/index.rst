========
 Stream
========

Transport conventions shared by the AXI4-Stream implementations of
the internet protocol suite:

* ``stream_config()`` builds the AXI4-Stream configuration every
  layer uses: 1, 2 or 4 bytes of data, keep, last, and a 1-bit user
  flag;

* the user flag, meaningful on the last beat only, marks a packet
  that must be discarded.  Only whole-packet validators (FCS,
  internet checksum over a full PDU) set it; every other rejection
  happens by not forwarding the packet;

* inter-layer streams are sequences of blocks, each on an integer
  count of beats: the uninterpreted headers of the layers below
  (their lengths listed in the layer's ``header_length_c`` generic),
  the boundary's own header or context, then the payload.
  ``context_byte_count()`` gives the transported size of a block
  list at a given width; blocks are tail-padded, except the ethernet
  frame block, front-padded and defined in the `stream_mac
  <../stream_mac/index>`_ package;

* a layer never originates slowdown: input ready only follows
  output-side backpressure, beyond a bounded per-packet fixed cost;

* fixed-size, symmetrical context blocks handed between layers, with
  their serialization functions.

``stream_block_resizer`` repacks packets between two widths of the
suite, re-deriving the block padding for the output width, so
byte-position parsers (control-plane endpoints like `DHCP
<../stream_dhcp/index>`_) can be written once at width one and sit
behind any stack width.  It moves one byte per cycle and is not
meant for forwarding paths.
