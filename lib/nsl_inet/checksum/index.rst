==========
 Checksum
==========

Internet checksum (RFC 1071) implementation, as a set of functions
usable both in synthesizable dataflow code and in testbenches:

* ``checksum_update()`` accumulates one byte or a byte string into an
  accumulator, allowing byte-per-cycle accumulation in hardware, with
  a two-byte fast path;

* ``checksum_spill()`` finalizes the accumulator into the two-byte
  field to store in a header, with support for odd-length data;

* ``checksum_acc_is_valid()`` and ``checksum_is_valid()`` verify a
  received blob.

These functions back the IP header verification in the ipv4 receiver,
the transmit-side `ipv4 checksum inserter <../ipv4/index>`_, and the
packet crafting functions of the ipv4, udp and testing packages.
