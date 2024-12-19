================
BNOC CRC tooling
================

BNOC CRC relies on `generic crc module <../../nsl_data/crc/>`_. It is
flexible in terms of width, polynom, initial value, serialization
options, etc.

CRC can be automatically computed on a `framed
<crc_framed_adder.vhd>`_ bus or a `committed
<crc_committed_adder.vhd>`_ bus.

CRC can be checked on a `committed <crc_committed_adder.vhd>`_ bus, in
such case, data are handled through a pipeline, and commited late
cancellation tells whether frame was actually correct.
