
Address and address vector abstraction
======================================

Address
-------

An address can be any bit width from 1 to 64 bits. It is declared in
the package as 64-bit unsigned, but only a subset should be referenced
and updated to ease optimization, as it is for the rest of the
library.

Address parsing and masking
---------------------------

When specifying address in code, this will most probably be to
implement a routing table where a set of ranges will target a set of
output ports.

Main idea in this library is to have a vector of addresses with
optional dont care bits, and associate exactly one entry with an
output port.  This somehow restricts the way to allocate addresses,
but enhances address matching and decoding.

Conceptually, we may have a router with 4 output ports and allocate
them these ranges:

======================== ====
Range                    Port
======================== ====
0x00000000 to 0x000fffff    0
0x40000000 to 0x40000fff    1
0x40001000 to 0x02001fff    2
0x20000000 to 0x200fffff    3
======================== ====

This can be rewritten as:

=================================== ====
Address (binary)                    Port
=================================== ====
00000000 0000---- -------- --------    0
01000000 00000000 0000---- --------    1
01000000 00000000 0001---- --------    2
00100000 0000---- -------- --------    3
=================================== ====

In order to express this with minimal effort, NSL gives some address
parsing syntactic sugar.  Address passed to functions can be of two
forms, either binary or hex.  In both cases, it may be followed by a
mask counting the number of significant bits from MSBs.

Examples:

* ``x"dead0000"`` will be expanded to a binary string as the language
  specifies (this is a language feature). This literal is equivalent
  to ``"11011110101011010000000000000000"`` when it reaches the function
  code.

* ``"xdead0000"`` will be interpreted as a hex string by the address
  handling function itself.

* ``"xdead----"`` will be interpreted as a hex string, and dont-care
  nibbles will expand as ``"----"`` (this is not covered by VHDL LRM).

* ``"xdead0000/16"`` will be interpreted as a hex string as well, but
  here, 16 MSBs are used, and 16 LSBs are dont cares. It ends up being
  equivalent to previous item.

* ``"xde-d0000/16"`` is equivalent to
  ``"11011110----1101----------------"``. This allows easy writing of
  sparse masks.

Address vectors
---------------

Address vectors can be created manually, or by calling
``routing_table()`` function. It accepts from 1 to 16 address strings as
argument and yields a vector of relevant length.

Lookup
------

To ease lookup in an address vector, two functions can be
used.

* ``routing_table_lookup()`` gives the index of the entry matching the
  address.  It may return a default value when passed address does not
  match any entry.

* ``routing_table_matches_entry()`` tells whether given address matches
  a given index of a routing table.
