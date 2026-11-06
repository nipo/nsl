=========================
DE25-Nano HPS lwh2f check
=========================

The Agilex 5 HPS through :vhdl:component:`hps_wrapper
<nsl_altera.hps.hps_wrapper>`, with the HPS IO of Terasic's golden
reference design and a register map on the lightweight HPS to fabric
bridge.  There is no HPS memory.

``hps.yaml`` describes the HPS: reference design settings, without its
EMIF and with lwh2f as the only bridge.  The build generates the atom
layer and the HPS boot configuration assignment from it.

Registers, 32-bit, at the start of the lwh2f window:

- 0: ``0x4e534c48`` ("NSLH");
- 1: scratch, bit 0 lights ``LED1``;
- 2: system manager general purpose output register.

``LED0`` is lit while the HPS holds the fabric in reset.

Building
========

::

  gbs -C example/terasic_de25_nano/hps_lwh2f_check project build

Clean the build directory before rebuilding: Quartus may crash on an
incremental build (``DDM_T::verify_token``).
