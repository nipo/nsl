=======================
DDR3 bringup on Artix-7
=======================

Test platform: XC7A50T-FGG484

RAM Part
========

An AS4C128M8D3LB behind ``nsl_ext_ram.ddr3_io.ddr3_phy_serdes``, one
byte lane, one strobe pair, DDR3-800.

Clocks
======

One MMCM makes everything from a 25 MHz oscillator::

  100 MHz   controller, one cycle per burst of eight
  400 MHz   memory rate: CK, commands, the strobe
  400 MHz   the same, a quarter period behind: data and mask
  200 MHz   what the input delay lines calibrate against

Settings
========

What this board measured of the PHY is one constant in
``src/boundary.vhd``, handed to ``ddr3_phy_serdes`` as its ``board_c``
generic::

  constant board_c: nsl_ext_ram.ddr3_io.serdes_board_t := (
    read_offset => 53,
    read_tap => 13,
    write_slip => 0,
    dq_enable_lead => 6,
    dqs_enable_lead => 14,
    strobe_invert => false
    );

Running
=======

Loading::

  gbs -t gbs.builtin.vivado=vivado:2022.2 project build
  acrobe chip -r hs2-/jtag/chain program --run ddr3.bit

Testing::

  acrobe run walk.py
  acrobe run poke.py
  acrobe run eye.py
  acrobe run mpr.py

  acrobe run drivemap.py
  acrobe run ruler.py
  acrobe run level.py
  acrobe run probe.py
  acrobe run taps.py
  acrobe run trace.py

Everything but ``walk.py`` in its default mode sweeps something, so
everything but that raises the panel's ``manual`` bit while it runs
and puts it back down at the end.

A script stopped part way leaves it up: the next ``walk.py`` then
measures whatever that script left, so program the part again before
believing a walk that followed one.

``poke.py``, ``level.py``, ``ruler.py`` and ``walk.py`` take the
strobe sense as a trailing ``0`` or ``1``; ``drivemap.py`` takes it
first and then the two leads.
