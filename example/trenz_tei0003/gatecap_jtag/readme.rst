===============================
CYC1000 JTAG gatecap transport
===============================

A gatecap rack on a Trenz CYC1000 (TEI0003, ``10CL025YU256C8G``),
reached through the part's own TAP.  It carries the same panel as
``../gatecap_uart`` so the two transports answer the same questions,
but it needs nothing from the board beyond the JTAG the part is
configured through: no UART, and no fabric clock on the host side of
the link.

The transport sits on the USER0 chain through
``nsl_jtag.user_tap.jtag_user_tap``, which on this family instantiates
the ``cyclone10lp_jtag`` atom.  The 12 MHz oscillator on ``CLK12M``
clocks the system side of the transport, the instruments and the user
logic; TCK only clocks the transport's TAP side.

**No SignalTap.**  The atom takes the user chains away from Quartus's
SLD hub, so a design built on this transport cannot also carry
SignalTap or any virtual-JTAG IP.

Building
========

::

  gbs -C example/trenz_tei0003/gatecap_jtag project build

3042 logic elements of 24624, 2435 registers.  Timing closes with
39.8 ns of setup slack in the TCK domain and 69.8 ns on the
oscillator, both at 83.3 ns.

The top level carries four ports named ``altera_reserved_tck``,
``_tms``, ``_tdi`` and ``_tdo``, handed to the rack's ``chip_*``
ports.  The names are what Quartus requires for the atom's pad side;
it puts them on the dedicated JTAG pads (H3, J5, H4, J4) itself, so
``pins.tcl`` does not mention them.

Programming and talking to it
=============================

::

  acrobe chip -r tei-ara41546/jtag/chain/0 program gatecap_jtag.rbf
  PYTHONPATH=$HOME/projects/gatecap/host acrobe run panel.py

::

  rack fingerprint 0x00d2e50c
    block bridge
    block enumerator
    block rates
    block panel
    block registers
  rates {'board': 12000000}
  scratch 0x00000000 -> scratch_back 0x00000000  ok
  scratch 0xdeadbeef -> scratch_back 0xdeadbeef  ok
  scratch 0x5a5a5a5a -> scratch_back 0x5a5a5a5a  ok
  scratch 0xffffffff -> scratch_back 0xffffffff  ok
  ticks 176919151 -> 182941731, 6022580 in about half a second
  ping_count 0 -> 5 after 5 strobes
  button 1

The rack path is::

  tei-ara41546/jtag/chain/0/bnoc_continuous_transport/gatecap

``bnoc_continuous_transport`` is the acrobe application that drives
``nsl_jtag.continuous_transport`` on the part's first user IR, USER0
(``0x00C``) on a Cyclone 10 LP.  Programming the part again over the
same TAP with this design loaded works: the user chain does not get
in the configuration's way.
