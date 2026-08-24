=====
 ARP
=====

Address resolution for IPv4 over ethernet.  On the transmit path,
this layer turns the peer protocol (IP) address chosen by the upper
layer into the peer hardware (MAC) address the ethernet layer needs.

* `arp_ethernet <arp_ethernet.vhd>`_ implements the ARP protocol on a
  pair of layer-2 pipes and serves lookups through a framed
  request/response resolver interface.  It holds a resolution cache
  of generic-set size.  Target addresses that fall outside the local
  subnet (unicast address masked with netmask) are diverted to
  default gateway resolution when a gateway is set.  A notification
  input allows snooping peer addresses from received frames.

* `arp_resolver <arp_resolver.vhd>`_ sits on the datapath and
  replaces the protocol address in transmit frame headers with the
  corresponding hardware address, querying a resolver (typically
  ``arp_ethernet``) through the framed request/response pipes.  If
  resolution fails, the frame is dropped.  It is generic on hardware
  and protocol address lengths.
