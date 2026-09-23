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
  acrobe info enumerate -r tei-ara41546/jtag/chain
  PYTHONPATH=$HOME/projects/gatecap/host acrobe run panel.py

::

  Node tree:
    chain
      10CL025Y
        sld
          continuous_transport0
            gatecap
              bridge
                enumerator
                rates
                panel
                  registers

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
  ticks 516415974 -> 522445896, 6029922 in about half a second
  ping_count 0 -> 5 after 5 strobes
  button 1
