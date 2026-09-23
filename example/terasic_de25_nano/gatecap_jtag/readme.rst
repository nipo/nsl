=================================
DE25-Nano JTAG gatecap transport
=================================

A gatecap rack on a Terasic DE25-Nano (``A5EB013BB23BE4SCS``),
reached through the part's own TAP over the on-board USB Blaster 3.
It needs nothing from the board beyond the JTAG the part is
configured through, and no fabric clock on the host side of the link.

The transport sits behind Quartus's SLD hub, as the virtual JTAG node
``nsl_jtag.user_tap.jtag_user_tap`` instantiates on this family.  The
host selects the node with a USER1 scan and then runs the transport
under USER0.  The 50 MHz oscillator on ``CLOCK1_50`` clocks the
system side of the transport, the instruments and the user logic;
TCK only clocks the transport's TAP side.

The hub is inserted by Quartus and finds the TAP by itself, so the
top level carries no JTAG port.  It does add an
``altera_reserved_tck`` port, which is what ``clocks.sdc`` hangs the
TCK clock on.

Building
========

::

  gbs -C example/terasic_de25_nano/gatecap_jtag project build

1097 ALMs of 46800.  Timing closes with 11.9 ns of setup slack in the
TCK domain at 33.3 ns and 15.9 ns on the oscillator at 20 ns.

Programming and talking to it
=============================

::

  acrobe chip -r ub3-/jtag/chain/0 program gatecap_jtag.rbf
  PYTHONPATH=$HOME/projects/gatecap/host acrobe run panel.py

::

  rack fingerprint 0x00b06d7c
    block bridge
    block enumerator
    block rates
    block panel
    block registers
  rates {'board': 50000000}
  scratch 0x00000000 -> scratch_back 0x00000000  ok
  scratch 0xdeadbeef -> scratch_back 0xdeadbeef  ok
  scratch 0x5a5a5a5a -> scratch_back 0x5a5a5a5a  ok
  scratch 0xffffffff -> scratch_back 0xffffffff  ok
  ticks 62571925 -> 87678610, 25106685 in about half a second
  ping_count 0 -> 5 after 5 strobes
  button 0
