==========
ROM blocks
==========

`rom_bytes`_ is a single-port ROM implemented through initialized
block RAMs. Read port has an arbitrary byte count.

Initial contents are given through generic as a byte string. When
memory is multi-byte, endianness of the byte string that initializes
the ROM can be selected.

.. _rom_bytes:

.. vhdl:autocomponent:: nsl_memory.rom.rom_bytes

`rom_bytes_2p`_ is the same ROM with twin reading ports.  They read
the same storage with the same contents, but can have different
addresses.

.. _rom_bytes_2p:

.. vhdl:autocomponent:: nsl_memory.rom.rom_bytes_2p
