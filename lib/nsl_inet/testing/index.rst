=========
 Testing
=========

Simulation-only helpers for exercising the stack in testbenches:

* frame dumpers (``ethernet_dump()``, ``ip_dump()``, ``arp_dump()``,
  ``icmp_dump()``, ``udp_dump()``, ``tcp_dump()``), decoding a byte
  string and logging it in human-readable form, verifying FCS and
  checksums on the way;

* PCAP file reading (``pcap_read()``), to replay captures taken with
  wireshark/tcpdump as stimulus;

* full-frame crafting (``udp_frame_pack()``,
  ``arp_reply_frame_pack()``), building on the per-layer ``*_pack()``
  functions from the protocol packages.
