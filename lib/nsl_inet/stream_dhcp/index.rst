=============
 Stream DHCP
=============

DHCPv4 client for the AXI4-Stream protocol suite (RFC 2131), an
application-contract endpoint on UDP port 68:

* ``stream_dhcp_client`` acquires a lease through DISCOVER, OFFER,
  REQUEST and ACK, renews it at T1 (unicast to the leasing server)
  and T2 (broadcast), and reports the leased address, netmask,
  router and DNS server behind a validity flag.  While it holds no
  address it requests broadcast replies, which traverse the stack
  whatever address is configured.

The client is byte-wide; hosts with wider data paths place it behind
a `stream_block_resizer <../stream/index>`_ pair.  `stream_host
<../stream_host/index>`_ instantiates it, resizers included, behind
its ``dhcp_c`` generic.

RELEASE, DECLINE and the pre-use ARP probe are not implemented.
