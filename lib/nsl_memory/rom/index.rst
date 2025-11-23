
===
ROM
===

* `rom_bytes <rom_bytes.vhd>`_ is a single-port ROM implemented
  through initialized block RAMs.  Initial contents are given through
  generic as a byte string.

* `rom_bytes_2p <rom_bytes_2p.vhd>`_ is the same ROM with twin reading
  ports.  They read the same storage with the same contents, but can
  have different addresses.
