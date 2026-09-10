IPv4 host over 10BASE-T without a Phy
=====================================

Runs a full IPv4 host on a Sipeed PMOD-Ethernet (HanRun HR911130A
magnetics, no Phy chip) plugged in J6, using only FPGA fabric and IOs.

``nsl_sipeed.pmod_ethernet`` carries the wire, from the pads up to an
axi4-stream of wire-level frames, and ``stream_ipv4_host`` carries the
stack: ARP, ICMP echo and a DHCP client.  The board acquires its
address from the network and answers pings.

Clocking
--------

Two domains meet through dual-clock stream fifos:

* the line domain, 100 MHz, oversamples the wire for the MAU (the MAU
  wants a multiple of 20 MHz, and its manchester receiver wants at
  least eight samples per bit),
* the core domain rides the 50 MHz board clock and carries the stack,
  which closes well below the line rate.

``timing.sdc`` constrains both and declares them asynchronous.  This
matters: the nets behind the clock buffer and the PLL are not
constrained by the board's ``clk.sdc``, so without it the tool assumes
a default rate, never optimizes for the real one, and the stack
silently emits corrupted headers.

Instrumentation
---------------

A gatecap rack rides the UART at 1 Mbaud, over HDLC.  ``status.py``
dumps the panel::

  acrobe run status.py

  link up     : True
  dhcp lease  : True
  address     : 10.0.0.161
  netmask     : 255.255.254.0
  router      : 0.0.0.0
  dns         : 10.0.0.254
  rx frames   : 59
  rx accepted : 59
  tx frames   : 3

The logic analyzer samples the raw line in its own domain::

  acrobe gatecap -r "tty-cu.usbserial-XXXX/serial(rate=1000000)/hdlc/addr00/gatecap" \
    capture line.sample.control --trigger tx_en=rising --count 512 --pretrigger 8

Its buffer is kept short so the analyzer closes timing at the line
rate; a link pulse fits, a whole frame does not.

The MAU defers to the medium and backs off, but its collision
detection is disabled here: the receive comparator has no amplitude
squelch, so this station's own transmission couples through the
magnetics and would read as a permanent collision.  Deference alone
keeps the two directions apart on a point-to-point link, and the
panel's collision counters stay at zero.

Notes
-----

Clearing ``use_dhcp_c`` uses the static address constants instead.

The UDP service port is a sink.  A loopback echo needs a fifo deep
enough for a whole datagram, and a single-clock ``axi4_stream_fifo``
that deep corrupts every sixteenth byte on this device, while a
shallower one head-of-line blocks the whole UDP receive path, DHCP
included, on the first oversized datagram.
