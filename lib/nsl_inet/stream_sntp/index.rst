=============
 Stream SNTP
=============

SNTP client for the AXI4-Stream protocol suite (RFC 4330), an
application-contract endpoint on a host UDP port:

* ``stream_sntp_client`` polls a unicast server and maintains a
  running 64-bit NTP timestamp behind a validity flag: the server
  transmit timestamp is latched as-is, then the seconds advance on a
  local one-second ticker until the next poll.  No clock discipline
  is attempted.  Replies must echo the request nonce;
  kiss-o'-death replies are ignored.

The client is byte-wide; it connects directly to a width-one host
port pipe, or behind a `stream_block_resizer <../stream/index>`_
pair on wider stacks.  The server address typically comes from the
`DHCP client <../stream_dhcp/index>`_ NTP servers option.
