Concise Binary Object Representation (CBOR)
===========================================

This is the encoding defined in `RFC 8949`_.

.. _RFC 8949: https://www.rfc-editor.org/rfc/rfc8949.html

Byte-based parser
-----------------

Typical use case in a streaming environment is to consume the
bytestream one byte at a time by calling ``feed()`` on a ``parser_t``
record.  ``is_last`` will tell whether item header is complete at this
cycle.  On subsequent cycle, ``kind()``, ``arg()`` and ``arg_int()``
will give out the details of the item.  For items containing data
(BSTR, TSTR), it is caller's responsability to consume data length
before returning to parsing an item.

Diagnostic pretty-printer
-------------------------

``cbor_diag()`` will parse a byte stream of valid CBOR-encoded data
and will return a test string containing diagnostic
representation. Example:

.. code:: vhdl

   log_info("diag: " & cbor_diag(from_hex("bf6346756ef563416d7421ff")));
   -- prints "diag: {_ "Fun": true, "Amt": -2}"

Encoder
-------

Functions ``cbor_positive()``, ``cbor_negative()``, ``cbor_number()``,
``cbor_bstr()``, ``cbor_tstr()``, ``cbor_array_hdr()``,
``cbor_map_hdr()``, ``cbor_tag_hdr()``, ``cbor_simple()``,
``cbor_true``, ``cbor_false``, ``cbor_null``, ``cbor_undefined``,
``cbor_break`` will spill relevant item headers. Examples:

.. code:: vhdl

   a := cbor_number(1);
   a := cbor_simple(255);
   a := cbor_null;
   a := cbor_false;

``cbor_array()`` can encode an array up to 32 first-level items. Example:

.. code:: vhdl

   a := cbor_array(cbor_number(1), cbor_number(2));

``cbor_map()`` can encode a map up to 32 pairs of items. Example:

.. code:: vhdl

   a := cbor_map(cbor_number(1), cbor_number(2), cbor_number(3), cbor_number(4));

``cbor_array_undef()`` and ``cbor_map_undef()`` can encode undefinite
arrays and maps. They should be passed a concatination of all contents
encoded values or pairs. Example:

.. code:: vhdl

   a := cbor_map_undef(cbor_tstr("Fun") & cbor_true
                       & cbor_tstr("Amt") & cbor_number(-2));

``cbor_tagged()`` encodes one tag with one contained item. Example:

.. code:: vhdl

   a := cbor_tagged(32, cbor_tstr("http://www.example.com"));

Limitations
-----------

Diagnostic representation of floats is not handled. Decoder still
handles them, but user is responsible for parsing the argument data.
