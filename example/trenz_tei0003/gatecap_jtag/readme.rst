===============================
CYC1000 JTAG gatecap transport
===============================

A gatecap rack on a Trenz CYC1000 (TEI0003, ``10CL025YU256C8G``),
reached through the part's own TAP.  It carries the same panel as
``../gatecap_uart`` so the two transports answer the same questions,
but it needs nothing from the board beyond the JTAG the part is
configured through: no UART, and no fabric clock on the host side of
the link.

The transport sits behind Quartus's SLD hub, as the virtual JTAG node
``nsl_jtag.user_tap.jtag_user_tap`` instantiates on Altera parts.  The
node reports NSL's manufacturer and the type of a continuous transport
carrying gatecap, so acrobe finds it by enumerating the hub.  The
12 MHz oscillator on ``CLK12M`` clocks the system side of the
transport, the instruments and the user logic; TCK only clocks the
transport's TAP side.

Building
========

::

  gbs -C example/trenz_tei0003/gatecap_jtag project build

3131 logic elements of 24624, 2473 registers.  Quartus inserts the hub
and its ``altera_reserved_*`` ports itself, so the top level carries
no JTAG port, and constrains TCK at 10 MHz before ``clocks.sdc`` is
read.  The TCK domain closes with 46.0 ns of setup slack at that
100 ns period, enough for the 83.3 ns acrobe drives, and the
oscillator with 69.1 ns at 83.3 ns.

Programming and talking to it
=============================

::

  acrobe chip -r tei-ara41546/jtag/chain/0 program gatecap_jtag.rbf
  PYTHONPATH=$HOME/projects/gatecap/host acrobe run panel.py

