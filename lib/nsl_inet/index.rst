=========================
 Internet protocol stack
=========================

Overview
========

``nsl_inet`` is an Ethernet/ARP/IPv4/UDP protocol stack.  Two
implementations coexist: the historical one over the `bnoc committed
<../nsl_bnoc/committed/index>`_ transport, described below, and a
sibling set of ``stream_*`` subsets over AXI4-Stream, described in
`The AXI4-Stream stack`_, which adds multi-byte data paths and a
line-rate ingress contract.

Frames are carried over the `bnoc committed
<../nsl_bnoc/committed/index>`_ transport, and every layer processes
them in a cut-through manner: a frame is never stored for
examination, it flows through each layer with minimal delay.  This
drives the two main design points of the stack:

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

The AXI4-Stream stack
=====================

The ``stream_*`` subsets reimplement the suite over `nsl_amba
AXI4-Stream <../nsl_amba/axi4_stream/index>`_, at data widths of 1, 2
or 4 bytes, keeping the cut-through philosophy while targeting
multi-gigabit line rates.  The conventions live in `stream
<stream/index>`_; the main points:

* inter-layer streams are sequences of beat-aligned *blocks*: the
  uninterpreted headers of the layers below, the boundary's own
  context, then the payload.  A layer forwards the listed blocks
  verbatim and only ever consumes its own header, so layers compose
  the way the bnoc stack composes, at any width, with no
  realignment logic anywhere;

* late cancellation maps to a single user bit carried on the last
  beat.  Only whole-packet validators (FCS, internet checksum over a
  full PDU) set it; every other rejection happens by not forwarding
  the packet.  The mac transmitter turns the flag into a corrupted
  FCS, so cancellation reaches the wire;

* a layer never originates slowdown: receive-side ready only follows
  output-side backpressure, beyond a bounded per-packet fixed cost.
  Test benches enforce this with a backpressure assertion component;

* address resolution follows an oracle model (`stream_resolver
  <stream_resolver/index>`_): applications hand the stack entry
  point their peer information, layer context and PDU; the entry
  queries a resolver — `ARP <stream_arp/index>`_ or a static table —
  and prepends the response blocks.  Protocol layers stay
  resolution-agnostic, and responders simply echo the symmetrical
  context of the packets they answer.

`stream_host <stream_host/index>`_ bundles the whole stack;
protocol layers are instances of the ``nsl_amba`` stream router,
which peels a header, consults external decision logic and inserts
a response header while the payload keeps streaming.

Compared to the bnoc stack, fragmentation, IPv4 options and
multicast are not handled, the UDP transmit checksum is sent as
zero, and TCP-oriented buffering is out of scope.

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

* `stream_resolver <stream_resolver/index>`_: address resolution
  service keeping the protocol layers resolution-agnostic, with the
  stack entry point and a static resolver;

* `stream_arp <stream_arp/index>`_: ARP, the dynamic implementation
  of the resolution contract;

* `stream_udp <stream_udp/index>`_: AXI4-Stream UDP layer with port
  dispatch;

* `stream_host <stream_host/index>`_: turnkey AXI4-Stream IPv4 host
  bundling the whole stack;

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
   stream_resolver/index
   stream_arp/index
   stream_udp/index
   stream_host/index
   testing/index
   switching/index
