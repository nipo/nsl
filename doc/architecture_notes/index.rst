==================
Architecture notes
==================

Per-vendor rules a port has to obey and that no datasheet states: what
a tool refuses, what a primitive does that its documentation does not
say, and where a vendor's simulation model and its silicon disagree.

Each entry says what the rule is, what it costs when broken -- the
tool's error code where there is one -- and what the evidence is: a
primitive, a vendor document section, or a file in this tree.  Figures
that were measured rather than read name the board they were measured
on.

Notes available:

* ``gowin/`` -- Arora V (GW5A), with GW1N/GW2A where they differ.

Xilinx and Lattice notes are not written yet.
