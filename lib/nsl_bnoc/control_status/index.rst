=======================
 Framed Control/Status
=======================

Control/status is a module providing access to a bunch of
configuration and status 32-bit registers. They are accessed through a
pair of framed interfaces. One frame is sent to the module, it
contains one or many read and write commands, response is sent back on
response stream, in order.

There are at most 128 registers. MSB of command gives the operation,
either write (1) or read (0). LSBs are the register number.  Write
commands are followed by 4 data bytes, little-endian.  Read responses
are followed by 4 data bytes, little-endian.

See info in `package <control_status.pkg.vhd>`_ for actual frame
format.
