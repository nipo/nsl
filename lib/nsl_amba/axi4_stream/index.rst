AXI4-Stream
===========

AXI4-Stream related definitions are located in the
:vhdl:package:`nsl_amba.axi4_stream` package.

Configuration
-------------

Configuration for AXI4-Stream is held in
:vhdl:type:`config_t <nsl_amba.axi4_streamconfig_t>` record type. It holds the
follwing settings:

* Data byte width, user, ID, dest width,
* keep, strb, ready and last support.

:vhdl:function:`config <nsl_amba.axi4_stream.config>` function can generate
such a configuration yet ensuring it makes sense.

AXI4-Stream recommends user bits are a multiple of data byte width,
but this is not a strong mandatory requirement. NSL does not enforce
this and lets the modules which do byte remapping or width changing
the option to map user bits in a custom way.

Signals
-------

Signals are split in the following records:

* Master output port (``master_t``) contains all master-driven signals:

  * ID,

  * data, strobe and keep,

  * user,

  * valid and last.

* Slave output port (``slave_t``) contains slave-driven signal:

  * ready.

A master transfer beat is encoded through calling
:vhdl:function:`transfer <nsl_amba.axi4_stream.transfer>` function.

Slave may extract all relevant fields through accessors
:vhdl:function:`is_valid <nsl_amba.axi4_stream.is_valid>`,
:vhdl:function:`is_last <nsl_amba.axi4_stream.is_last--23a73a85>`,
:vhdl:function:`id <nsl_amba.axi4_stream.id>`,
:vhdl:function:`user <nsl_amba.axi4_stream.user>`,
:vhdl:function:`dest <nsl_amba.axi4_stream.dest>`. Master may use
:vhdl:function:`is_ready <nsl_amba.axi4_stream.is_ready>`.

For data/strb/keep, like AXI4-MM, encoding and extraction can specify
byte order or consider transfer as an unsigned value.

Simulation tools
----------------

For simulation purposes, there are
:vhdl:procedure:`nsl_amba.axi4_stream.send--93484ed4` (:ref:`[alt]
<send--f03ab1ab>`) and :vhdl:procedure:`nsl_amba.axi4_stream.receive`
procedures that can transfer one beat from/to a stream.

For full packets, there are :vhdl:procedure:`packet_send
<nsl_amba.axi4_stream.packet_send>` and
:vhdl:procedure:`packet_receive
<nsl_amba.axi4_stream.packet_receive--08b6b291>` procedures.  For read
data, :vhdl:procedure:`packet_receive
<nsl_amba.axi4_stream.packet_receive--e1261cc1>` will dynamically
allocate a :vhdl:type:`nsl_data.bytestream.byte_stream` or may receive
an output :vhdl:type:`nsl_data.bytestream.byte_string`. In the latter
case, frame should have exactly the expected length.

For usage examples, see ``test/amba/axi4_stream_*`` test benches
implementation.

There is a protocol assertion tester in component
:vhdl:component:`axi4_stream_protocol_assertions
<nsl_amba.axi4_streamaxi4_stream_protocol_assertions>`.  It implements
all relevant checks from ARM's DUI 0534-B.

There is a text dumper in :vhdl:component:`axi4_stream_dumper
<nsl_amba.axi4_streamaxi4_stream_dumper>`.  It dumps stream data to
simulation log.

:vhdl:component:`axi4_stream_pacer
<nsl_amba.axi4_streamaxi4_stream_pacer>` can reduce pace of a stream
by gating handshaking with a fixed probability.  It allows to debug
handshaking logic errors.


Buffer helper
-------------

.. image:: axis_buffer2.svg
  :width: 400
  :alt: A AXI-Stream buffer

When sending/receiving long packets with a header of fixed size, it
may be practical to send/receive the header independently of the bus
data width.  :vhdl:type:`buffer_t <nsl_amba.axi4_stream.buffer_t>` is
such an helper.  It should be configured as a constant of type
:vhdl:type:`buffer_config_t <nsl_amba.axi4_stream.buffer_config_t>`.
One given buffer context can be used for both send and receive.
:vhdl:function:`reset <nsl_amba.axi4_stream.reset--ab93436a>` will
reset count of data bytes to exchange.  When preparing for sending,
data vector should be passed.  Reset will accept data vector is any
byte order.

Until :vhdl:function:`is_last
<nsl_amba.axi4_stream.is_last--ca79387f>` returns the current beat is
the last one, :vhdl:function:`next_beat
<nsl_amba.axi4_stream.next_beat>` will generate :vhdl:type:`master_t
<nsl_amba.axi4_stream.master_t>` record for sending.  In order to
compute next step and next data, :vhdl:function:`shift
<nsl_amba.axi4_stream.shift--b1753abd>` should be used, either passing
input beat (for reading from slave) or arbitrary data for sending :vhdl:function:`shift
<nsl_amba.axi4_stream.shift--640af5fc>` (can
be left unspecified).

Serialization tools
-------------------

.. image:: axis_packer.svg
  :width: 400
  :alt: AXI-Stream packer model

For (un)packing a AXI4-Stream to a vector of bits, there are
:vhdl:function:`vector_length <nsl_amba.axi4_stream.vector_length>`,
:vhdl:function:`vector_pack <nsl_amba.axi4_stream.vector_pack>` and
:vhdl:function:`vector_unpack
<nsl_amba.axi4_stream.vector_unpack>`. All three will accept any
letter from "idskouvl", in any order.  They will respectively tell ID,
Data, Strb, Keep, Dest, User, Valid and Last need to be encoded.  If
some fields are disabled in configuration, they need not to be encoded
and will yield 0 data bits.  :vhdl:function:`vector_pack
<nsl_amba.axi4_stream.vector_pack>` will encode one stream beat as a
:vhdl:type:`std_ulogic_vector
<ieee.std_logic_1164.std_ulogic_vector>`,
:vhdl:function:`vector_unpack <nsl_amba.axi4_stream.vector_unpack>`
will decode a :vhdl:type:`std_ulogic_vector
<ieee.std_logic_1164.std_ulogic_vector>` as a stream beat,
