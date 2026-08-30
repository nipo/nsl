=========================
 Internet protocol stack
=========================

Overview
========

``nsl_inet`` is an Ethernet/ARP/IPv4/UDP protocol stack.  Frames are
carried over the `bnoc committed <../nsl_bnoc/committed/index>`_
transport, and every layer processes them in a cut-through manner: a
frame is never stored for examination, it flows through each layer
with minimal delay.  This drives the two main design points of the
stack:

* frames can be cancelled late, after they started flowing.  This is
  what the committed transport provides: the last byte of every frame
  carries a validity bit, and a frame that fails a check (bad FCS,
  bad header, unhandled destination) is forwarded with the validity
  bit cleared rather than being cancelled in place;

* frame context must be known as early as possible.  The context a
  layer extracts on receive (peer addresses, protocol selection) is
  summarized at the head of the frame handed to the upper layer, so
  the upper layer can take its decisions before the payload flows.

Layer-1 interfaces (MII, RMII, GMII) are not part of this library,
see `nsl_mii <../nsl_mii/index>`_.

Layer composition
=================

All layers share the same interface contract:

* a layer receives frames prefixed with a fixed-length header it does
  not interpret.  The header length is set by a generic; the layer
  passes the header through untouched;

* on the receive path, a layer strips its own protocol fields and
  appends its resolved context to the pass-through header, so the
  upper layer sees a longer header;

* on the transmit path, the reverse happens: the layer consumes the
  context appended by the upper layer and crafts its protocol fields
  from it;

* the last byte of every frame is a status byte whose bit 0 is the
  committed validity bit.

For instance, with an optional layer-1 pre-header, the frame handed
upwards at each boundary of the receive path is::

  from L1:   | L1 pre-header | DA, SA, ethertype | payload | FCS    | status |
  mac:       | L1 pre-header | DA, SA, ethertype | payload          | status |
  ethernet:  | L1 pre-header | peer MAC, ctx | L3 PDU              | status |
  IPv4:      | ... | peer MAC, ctx | peer IP, ctx, proto, size | L4 PDU | status |
  UDP layer: | ... | peer MAC, ctx | peer IP, ctx, proto | remote port | data | status |

This contract makes the stack composable: a layer only needs to know
the total length of the headers below it, not their meaning.  New
ethertypes can be plugged next to IPv4, new IP protocols next to UDP.

The exact frame structure at each boundary is documented in every
subset's ``*.pkg.vhd`` file; those comments are the reference.

Checksum handling
=================

The internet checksum is the one place where pure cut-through cannot
hold: the checksum sits in the header of a packet but covers data
that comes after it.  `checksum <checksum/index>`_ implements the
checksum computation itself; `ipv4 <ipv4/index>`_ hosts
``ipv4_checksum_inserter``, which computes IP/ICMP/UDP/TCP checksums
while the packet traverses a fifo and rewrites the header fields on
the way out.  Only the checksums bypass the storage; the rest of the
design stays cut-through.

Contents
========

* `func <func/index>`_ is the turnkey entry point: ``ethernet_host``
  bundles the whole stack and exposes one committed pipe pair per UDP
  service port or IP protocol declared through generics;

* the protocol layers:

  * `mac <mac/index>`_: FCS and minimal frame size, transparent to
    addresses and ethertype;

  * `ethernet <ethernet/index>`_: host adaptation — destination
    address filtering, peer/context compression, ethertype dispatch;

  * `vlan <vlan/index>`_: 802.1Q tag insertion/removal and per-VID
    dispatch, between mac and ethernet;

  * `arp <arp/index>`_: IPv4-over-ethernet address resolution, with
    cache and default-gateway diversion;

  * `ipv4 <ipv4/index>`_: IPv4, ICMP echo responder, checksum
    inserter;

  * `udp <udp/index>`_: UDP with per-port dispatch;

* `checksum <checksum/index>`_: internet checksum functions;

* `stream <stream/index>`_: transport conventions for the
  AXI4-Stream implementations of the suite;

* `stream_mac <stream_mac/index>`_: AXI4-Stream mac layer, FCS and
  minimal frame size;

* `stream_ethernet <stream_ethernet/index>`_: AXI4-Stream ethernet
  layer, address filtering, context compression and ethertype
  dispatch;

* `stream_ipv4 <stream_ipv4/index>`_: AXI4-Stream IPv4 layer with
  protocol dispatch, and the ICMP echo responder;

* `testing <testing/index>`_: packet crafting, decoding and PCAP
  reading for testbenches;

* `switching <switching/index>`_ is the odd one out: a
  store-and-forward 802.1D transparent bridge over AXI4-Stream, not a
  committed cut-through component.

.. toctree::

   mac/index
   ethernet/index
   vlan/index
   arp/index
   ipv4/index
   udp/index
   func/index
   checksum/index
   stream/index
   stream_mac/index
   stream_ethernet/index
   stream_ipv4/index
   testing/index
   switching/index
