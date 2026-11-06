=====================
 Agilex 5 HPS wrapper
=====================

:vhdl:component:`hps_wrapper <nsl_altera.hps.hps_wrapper>` is a plain
VHDL instantiation of the Agilex 5 hard processor system, without
Platform Designer nor the ``intel_agilex_5_soc`` IP.  It instantiates
the ``tennm_soc_hps`` atom, the ``tennm_sm_soc_mpfe`` atom when a
bridge or the HPS memory needs it, and buffers on the HPS dedicated
IO.  It exposes the fabric side of the HPS as NSL records.

The wrapper source is only registered for Agilex 5 parts
(``target_part`` matching ``A5E*``).  There is no simulation model of
the HPS.  The package and the bridge pipelines are available
everywhere.

The HPS EMIF is not part of the wrapper: it is a Quartus generated
``emif_io96b_hps`` IP, connected to the wrapper's ``emif_o``/``emif_i``
records.

HPS configuration file
======================

The HPS is described by a YAML file of the project, of file type
``nsl-agilex5-hps``::

  sources:
    - file_type: nsl-agilex5-hps
      files:
        - hps.yaml

A pass of the NSL gbs plugin (``gbs.plugin.nsl.agilex5_hps``) turns it
into:

* the atom layer the wrapper instantiates, ``hps_atoms`` in
  ``nsl_altera``.  The HPS atom only accepts an unconnected input where
  it has no hard route (HPS IO inputs of pins without input buffer, the
  MPFE link without MPFE), and Quartus only leaves a port unconnected
  when the component does not declare it.  Which ports are declared
  depends on the configuration, hence the generation;
* the ``HPS_ISW_DATA`` global assignment of the Quartus project, the
  boot configuration the SDM hands over to the first stage boot loader.

Wrapper generics must agree with the file (bridges in use and their
data width, HPS memory), elaboration fails otherwise.

The file holds, every key being mandatory unless stated otherwise::

  cpu:
    a55: true                 # cores 0 and 1 powered
    a76_core2: true
    a76_core3: true
    boot_core: 0              # 0 or 2
    l3_cache_mb: 1            # 0 to 2
    mpu_frequency_hz: 533330000
  peripherals: [usb0, emac0, sdmmc]   # others are power gated, among
                                      # usb0, usb1, emac0..2, nand,
                                      # sdmmc, coresight
  watchdog_reset: cold        # cold, warm or remote_update
  emif:                       # optional, HPS memory
    topology: 1x32            # 1x16 or 1x32
  bridges:                    # optional, the ones in use
    h2f: {data_width: 128, address_width: 38}
    lwh2f: {data_width: 32, address_width: 29}
    f2h: {data_width: 256, address_width: 32}
    f2sdram: {data_width: 256, address_width: 32}
  pins:                       # all of 0 to 47
    0: {select: 1, mode: input}
    14: {select: 0, mode: input, input_delay: 117}
    36: {select: 4, mode: i2c}
    ...
  use_fpga: []                # optional, peripherals routed to the
                              # fabric (pinmux usefpga entries)
  clock_manager:              # every entry of the handoff
    mainpllgrp.nocclk.src: 0
    ...
    hps_osc_clk_hz: 25000000
    fpga_clk_hz: 125000000

Pin ``select`` is the pinmux pinsel value giving the pin its function,
``mode`` tells which buffers the pin gets: ``unused``, ``input``,
``output``, ``bidir``, ``bidir_open_drain``, or ``i2c`` (the HPS output
drives the line low when set).  Clock manager entries are the values
the vendor IP computes from the clock frequencies asked for; nothing is
computed here, they are taken from a vendor generated handoff.

The address width sets the bridge window of h2f and lwh2f, and the
address width the HPS takes on f2h and f2sdram, from 20 bits.

HPS IO
======

HPS IO pin ``n`` is numbered as in the handoff: 0 to 23 are
``HPS_IOA_1`` to ``HPS_IOA_24``, 24 to 47 are ``HPS_IOB_1`` to
``HPS_IOB_24``.  The project locates each used pin on its package
ball.  The pin mode in the configuration file selects the wrapper port
the pin goes through:

* ``hps_io_i(n)`` for ``input``,
* ``hps_io_o(n)`` for ``output``,
* ``hps_io_io(n)`` for ``bidir``, ``bidir_open_drain`` and ``i2c``,
  whose direction the HPS controls.

The top level port of the pin must have the same direction.  Quartus
adds its own buffers on a top level ``inout`` port, and the pad of an
output-only HPS pin has no route for an input buffer: the Fitter
fails.  Inputs and outputs may go through signals, bidirectional pins
need individual association of ``hps_io_io`` elements, unused ones to
a dummy signal.  Unused pins get no buffer.

Bridges
=======

* ``h2f``: HPS master, 32, 64 or 128-bit data, up to 38-bit address
  (:vhdl:constant:`h2f_native_config_c
  <nsl_altera.hps.h2f_native_config_c>`).
* ``lwh2f``: lightweight HPS master, 32-bit data, up to 29-bit
  address.
* ``f2h``: fabric master into the cache coherency unit, ACE5-Lite,
  256-bit data, up to 40-bit address.  Domain and snoop fields are
  constant, from ``f2h_ace_c``.
* ``f2sdram``: fabric master into the HPS memory, 64, 128 or 256-bit
  data, up to 40-bit address.  Needs ``emif_used_c``.

Each bridge has a ``*_used_c`` generic, matching the configuration
file.  An unused bridge is not configured in the HPS and its ports are
idle.

Each bridge has a ``*_config_c`` generic setting the configuration of
its records, defaulting to the native one.  It may differ from native
only where conversion is trivial, elaboration fails otherwise:

========================  ==========================  ======================
Field                     h2f, lwh2f (HPS master)     f2h, f2sdram (HPS
                                                      slave)
========================  ==========================  ======================
data width                one the bridge supports     one the bridge
                                                      supports
address width             native or less, MSBs        native or less,
                          dropped                     zero-extended
ID width                  native or more,             native or less,
                          zero-extended               zero-extended
max length                256 or more                 256 or less
user                      unused                      8 or less
size, burst               mandatory                   optional
cache, qos, lock, region  optional                    optional
========================  ==========================  ======================

The bridge data width is set in the atoms from the configuration, no
software setting is involved.  On h2f and lwh2f, the address width
sets the size of the bridge window, from 20 bits: a narrower
configuration sees the window aliased.

Atom bridge ports have a ready latency.  As the vendor IP does, every
channel goes through a register stage in each direction, placed in
core/periphery boundary hyper-registers, and through a skid buffer of
7 beats on the receiving side
(:vhdl:component:`hps_bridge_channel
<nsl_altera.hps.hps_bridge_channel>`).  Response channels towards the
HPS have no skid buffer: the HPS takes the beats sent while its ready
was asserted two cycles before.

Without SMMU, the stream ID fields of f2h and f2sdram are tied as the
vendor IP ties them.

Clock domains and reset
=======================

Each bridge record is synchronous to its ``*_clock_i``.
``*_reset_n_o`` is the HPS reset (``h2f_reset``), asserted
asynchronously and released synchronously to the bridge clock.  It also
resets the bridge skid buffers.  ``reset_n_o`` is the same reset, not
synchronized.

``user_clock_o`` are the clock manager user clocks.

The warm reset handshake is acknowledged by the wrapper unless
``warm_reset_handshake_c`` is set, ``warm_reset_ack_i`` is then the
acknowledge.

Verification limits
===================

The generated atom layer elaborates under GHDL with the atoms left
unbound (``tests/altera/hps_atoms``).  The handoff string is checked
against the one the vendor IP generates for the Terasic DE25-Nano
golden reference design (plugin tests).  The bridge pipelines are
simulated.  Binding to the atoms only exists in a Quartus build.
