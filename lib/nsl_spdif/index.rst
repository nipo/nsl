========
 S/PDIF
========

S/PDIF is a digital audio interface for consumer market. It has a
professional counterpart called AES3 (or AES/EBU). They share the
link-layer encoding.  This library supports both.

S/PDIF uses blocks of 192 samples, each of them can be up to 24 bit
stereo.  NSL models the `block <blocker>`_ level.  A block may be
chunked into `frames <framer>`_, frames may be `serially transmitted
<serdes>`_.

Above those low level layers, a `transceiver <transceiver>`_ package
encapsulates the high-level service for SPDIF RX/TX.

NSL handles serdes clock recovery through oversampling.  It is able to
recover the stream clock rate from the wire encoding digitally.  This
relies on `tick helpers <../nsl_clocking/tick>`_ and `line coding NRZI
<../nsl_line_coding/nrzi>`_ helpers.

SPDIF or AES3 side-band user and channel data encoding/decoding are
supported. AES3 CRC can also optionally be asserted for.
