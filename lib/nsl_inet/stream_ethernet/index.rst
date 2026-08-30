=================
 Stream Ethernet
=================

Ethernet host adaptation for the AXI4-Stream implementation of the
internet protocol suite, following the conventions of the `stream
<../stream/index>`_ package.

Both boundaries are sequences of beat-aligned blocks.  The blocks of
the layers below, whose contents lengths are listed in the
``header_length_c`` generic, are forwarded verbatim in both
directions, padding bytes included.

On the mac side, a frame is ``[forwarded blocks][ethernet frame
block][L3 PDU]``, the frame block being ``ethernet_frame_offset()``
front-padding bytes followed by ``[DA][SA][ethertype]``.  There is no
FCS: checking and appending it is the job of the layer below.  On the
layer-3 side, a frame is ``[forwarded blocks][context block][L3
PDU]``, the context block being a tail-padded ``l2_context_t``.  There
is one layer-3 stream pair per entry of the ``ethertype_c`` generic,
and that table alone decides ethertypes, in both directions.

* ``stream_ethernet_receiver`` filters frames on destination address
  (local address, reported as unicast, or broadcast; multicast group
  addresses are dropped), dispatches them on ethertype, and replaces
  the frame block by the context block carrying the frame source
  address.  Mac padding is left in place for the layer above to
  ignore;

* ``stream_ethernet_transmitter`` funnels frames from every layer-3
  port, crafting the ethernet header from the context peer, the local
  address, and the ethertype of the port the frame came from.  The
  context casting field is ignored;

* ``stream_ethernet_layer`` pairs the two.

Both directions are built on ``nsl_amba.stream_routing``'s
``axi4_stream_router``, which peels the input header, hands it to the
address and ethertype decision logic, and inserts the output header.
The receive path never backpressures its input in steady state, and
the reject flag of a frame is forwarded unchanged.
