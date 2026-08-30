=================
 Stream resolver
=================

Address resolution service for the AXI4-Stream protocol suite.
Applications hand the stack a packet made of peer information, the
context of the layer they talk to, and their PDU; the entry point
queries a resolver with the peer information and prepends the
response — every block the layers below expect — leaving the
protocol layers agnostic to resolution.  Responders never resolve:
they echo the symmetrical context of the packets they answer.

* ``stream_resolver_entry`` splices resolution into an egress
  stream, holding the packet in its own buffer while the lookup
  runs, and dropping it when resolution fails;

* ``stream_resolver_arbiter`` shares one resolver between several
  query sources;

* ``stream_resolver_static_ipv4`` is the oracle of a fully static
  configuration, a constant address table;

* `stream_arp <../stream_arp/index>`_ is the dynamic implementation
  of the same contract.
