============
 Stream ARP
============

ARP over ethernet for IPv4, implementing the address resolution
contract of `stream_resolver <../stream_resolver/index>`_.
``stream_arp_resolver`` owns the 0x0806 pipe pair of the ethernet
layer: it answers ARP requests for the local station, learns from
traffic addressed to it, and resolves cache misses by emitting
broadcast requests with retries; exhausted retries answer the query
with the reject flag, so clients never hang.
