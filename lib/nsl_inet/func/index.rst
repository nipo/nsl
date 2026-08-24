==============
 Turnkey host
==============

`ethernet_host <ethernet_host.vhd>`_ assembles the whole stack —
ethernet, ARP, IPv4, ICMP and optionally UDP — into a single
component.  It is the intended entry point for designs that just need
network endpoints.

Generics declare the list of additional IP protocols and UDP service
ports; the component exposes one committed pipe pair per entry, plus
the layer-1 link.  The hardware address and the IP configuration
(unicast, netmask, gateway, broadcast) are runtime inputs.
