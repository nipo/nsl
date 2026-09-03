=============
 Stream host
=============

Turnkey IPv4 host over the AXI4-Stream protocol suite:
``stream_ipv4_host`` bundles the mac, ethernet, IPv4 and UDP layers,
the ICMP echo responder, and ARP resolution behind a per-port stack
entry.  Applications get one stream pair per UDP port: they transmit
``[IPv4 context][UDP context][payload]`` and receive the same
preceded by the lower-layer blocks; echoing the context blocks back
turns a received datagram into its reply.  The host answers pings
and ARP requests on its own.

With the ``dhcp_c`` generic set, the host runs a `DHCP client
<../stream_dhcp/index>`_ on an internal port 68 pipe and takes its
address from the lease instead of ``local_address_i``, reporting the
lease on the ``dhcp_*_o`` ports.
