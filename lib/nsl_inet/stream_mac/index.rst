============
 Stream MAC
============

Ethernet MAC framing for the AXI4-Stream protocol suite: frame check
sequence and minimum frame size, between a layer-1 interface and the
ethernet layer.

* ``stream_mac_receiver`` checks the FCS, strips it, and sets the
  reject flag on the last beat of frames with a bad FCS and of frames
  shorter than the minimum ethernet frame size.  It accepts one beat
  per cycle, back-to-back frames included;

* ``stream_mac_transmitter`` pads frames to the minimum ethernet frame
  size and appends the FCS.  A frame arriving with the reject flag set
  gets a corrupted FCS, so that the peer drops it.

Outgoing frames are padded to the minimum ethernet frame size and
further to the next beat boundary, so a frame may reach the wire up to
one byte short of a beat longer than strictly needed.  The padding is
covered by the FCS, and receivers trim it from the length field of the
protocol above, so the extra bytes are as invisible as the padding the
minimum frame size mandates.  At a one-byte width the two rules
coincide and frames keep their exact size.

Streams on both sides follow the block conventions of
``nsl_inet.stream``: the blocks whose contents lengths are
``header_length_c``, forwarded untouched, then the ethernet frame
block, made of the front pad, the ethernet header, the payload, and,
on the layer-1 side, the FCS.  The forwarded blocks and the front pad
are accounted for in neither the FCS nor the frame size.

This package owns the frame block geometry:
``ethernet_header_length_c`` and the ``ethernet_frame_offset()``
front pad, used by every component handling the mac-side stream.
