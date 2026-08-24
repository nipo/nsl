====================
 Ethernet switching
====================

Store-and-forward ethernet switching (802.1D-style transparent
bridge) over AXI4-Stream.  Unlike the rest of the library, this is
not a cut-through committed component: each ingress port stores a
complete frame in a cancellable buffer, so that bad frames and frames
hitting a full buffer are dropped atomically, and committed frames
are never dropped.

All ports share one clock domain and one data width of 1, 2 or 4
bytes.  The destination address is looked up in a shared MAC table
while the frame is being received; unknown, broadcast and group
destinations are flooded to all ports enabled in the flood mask
except the ingress port.

* `switching_bridge <switching_bridge.vhd>`_ is the complete switch:
  symmetric AXI4-Stream port pairs, a runtime flood mask, and either
  a learning MAC table or a static one passed as generics.  A
  management CPU attaches as an ordinary port and can opt out of
  flooding through the flood mask;

* `switching_ingress <switching_ingress.vhd>`_ is the per-port
  ingress: cancellable frame buffer, destination lookup, source
  learning, per-frame egress mask computation;

* `switching_mac_table <switching_mac_table.vhd>`_ is the shared MAC
  table, either learning source addresses of committed frames (with
  optional aging) or serving the static list;

* `switching_fabric <switching_fabric.vhd>`_ is the egress side: one
  round-robin arbiter per egress port over the ingress head-of-queue
  frames.  Multicast replays the frame from the ingress buffer once
  per destination port.

Elaboration-time configuration (stream width, port count, buffer
size, MAC table geometry, learning and aging) is grouped in a
``config_t`` record built by the ``config()`` function.
