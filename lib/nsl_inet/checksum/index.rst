==========
 Checksum
==========

Internet checksum (RFC 1071) implementation, as a set of functions
usable both in synthesizable dataflow code and in testbenches.

One parametric engine serves every chunk width, following the
config/state pattern of `nsl_data.crc <../../nsl_data/crc/index>`_:

* ``checksum_config()`` sizes the engine for a chunk byte count or
  directly from an AXI4-Stream configuration, one whole-beat add per
  beat at even widths;

* ``checksum_init()``, ``checksum_seed()``, ``checksum_update()``
  accumulate chunks, byte strings or stream beats — unkept beat
  bytes are masked to zero, so keep never gates the adder;

* ``checksum_is_valid()`` decides on the unreduced sum, a valid
  packet finalizing to the one's complement zero, the free compare
  of a DSP accumulator; ``checksum_finalize()`` and
  ``checksum_spill()`` reduce to the residue and the header field.

``checksum_byte_config_c`` is the one-byte chunk, the configuration of
the byte-per-cycle bnoc layers: the IP header verification of the ipv4
receiver, the transmit-side `ipv4 checksum inserter <../ipv4/index>`_,
and the packet crafting functions of the ipv4, udp and testing
packages.

A byte-serial family — ``checksum_acc_t``, ``checksum_update()``,
``checksum_acc_is_valid()``, ``checksum_is_valid()``,
``checksum_spill()`` — is a re-typing of that configuration into a
17-bit signed accumulator, kept as a compatibility surface.
``checksum_seed()`` bridges it to any configuration.  New code takes
the parametric family.

``checksum_stream_validator`` is a pass-through component verifying
every packet of an AXI4-Stream, flagging failures through the reject
bit of the `stream <../stream/index>`_ conventions.
