
AXI4-Stream
===========

AXI4-Stream related definitions are located in the
`nsl_amba.axi4_lite` package.

Configuration
-------------

Configuration for AXI4-Lite is held in `config_t` record type. It holds
the follwing settings:

* Data byte width, user, ID, dest width,
* keep, strb, ready and last support.

`config()` function can generate such a configuration yet ensuring it
makes sense.

AXI4-Stream recommends user bits are a multiple of data byte width,
but this is not a strong mandatory requirement. NSL does not enforce
this and lets the modules which do byte remapping or width changing
the option to map user bits in a custom way.

Signals
-------

Signals are split in the following records:

* Master output port (`master_t`) contains all master-driven signals:
  * ID,
  * data, strobe and keep,
  * user,
  * valid and last.

* Slave output port (`slave_t`) contains slave-driven signal:
  * ready.

A master transfer beat is encoded through calling `transfer()`
function.

Slave may extract all relevant fields through accessors `is_valid()`,
`id()`, `user()`, `dest()`. Master may use `is_ready()`.

For data/strb/keep, like AXI4-MM, encoding and extraction can specify
byte order or consider transfer as an unsigned value.

Simulation tools
----------------

For simulation purposes, there are `send()` and `receive()` procedures
that can transfer one beat from/to a stream.

For full packets, there are `packet_send()` and `packet_receive()`
procedures.  For returned value, `packet_receive()` will dynamically
allocate a `byte_stream`.

For usage examples, see `test/amba/axi4_stream_*` test benches
implementation.

There is a protocols assertion tester in component
`axi4_stream_protocol_assertions`.  It implements all relevant checks
from ARM's DUI 0534-B.

There is a text dumper in `axi4_stream_protocol_assertions`.  It dumps
stream data to simulation log.

`axi4_stream_pacer` can reduce pace of a stream by gating handshaking
with a fixed probability.  It allows to debug handshaking logic
errors.


Buffer helper
-------------

When sending/receiving long packets with a header of fixed size, it
may be practical to send/receive the header independently of the bus
data width.  `buffer_t` is such an helper.  It should be configured as
a constant of type `buffer_config_t`.  One given buffer context can be
used for both send and receive.  `reset()` will reset count of data
bytes to exchange.  When preparing for sending, data vector should be
passed.  Reset will accept data vector is any byte order.

Until `is_last()` returns the current beat is the last one,
`next_beat()` will generate `master_t` record for sending.  In order
to compute next step and next data, `shift()` should be used, either
passing input beat (for reading from slave) or arbitrary data for
sending (can be left unspecified).

Serialization tools
-------------------

For (un)packing a AXI4-Stream to a vector of bits, there are
`vector_length()`, `vector_pack()` and `vector_unpack()`. All three
will accept any letter from "idskouvl", in any order.  They will
respectively tell ID, Data, Strb, Keep, Dest, User, Valid and Last
need to be encoded.  If some fields are disabled in configuration,
they need not to be encoded and will yield 0 data bits.
`vector_pack()` will encode one stream beat as a `std_ulogic_vector`,
`vector_unpack()` will decode a `std_ulogic_vector` as a stream beat,
