=======================================
 Zynq UltraScale+ MPSoC PS wrapper
=======================================

:vhdl:component:`ps8_wrapper <nsl_xilinx.ps8.ps8_wrapper>` is a plain
VHDL instantiation of the Zynq UltraScale+ ``PS8`` primitive, without
Vivado block design nor zynq_ultra_ps_e IP.  It exposes the PL side of
the processing system as NSL records.

The wrapper source is only registered for Zynq UltraScale+ parts
(``target_part`` matching ``xczu*`` or ``xck*``).  There is no
simulation model of the processing system: the partition has no
simulation implementation of the wrapper.  The package is available
everywhere.

Configuration by software
=========================

The primitive has no configuration attribute: everything is set up by
software running on the PS (usually the first stage boot loader, from
``psu_init``) before the PL ports work:

* PL power-up and PS-PL isolation removal (``PMU_GLOBAL.REQ_PWRUP``),
* PL clock sources, dividers and enables (``CRL_APB.PLn_REF_CTRL``),
* AXI port data widths (``FPD_SLCR.AFI_FS``, ``LPD_SLCR.AFI_FS`` and
  AFIFM ``RDCTRL``/``WRCTRL``),
* PL resets, through EMIO GPIO bank 5 (``pl_reset_n_o``).

Until then, AXI ports behave as if disconnected: a design must not
expect handshakes from the PS before software ran.

Dedicated pins
==============

MIO, DDR, PS-GTR, ``PS_REF_CLK``, ``PS_POR_B`` and ``PS_SRST_B`` are
dedicated pins of the PS: they are left unconnected in the wrapper,
Vivado places them without PL routing.

The ``PS8`` instance carries ``DONT_TOUCH``: Vivado sees no side
effect in the cell, a design whose PL logic only talks to the PS,
without PL I/O, would otherwise be swept out entirely by
``opt_design``.

Interfaces
==========

* ``pl_clock_o``: the four PL clocks, each through a ``BUFG_PS``.  The
  PS8 clock outputs cannot reach fabric logic otherwise.

* ``pl_reset_n_o``: the four PL resets.  The PS8 has no dedicated PL
  reset output, Xilinx IP uses EMIO GPIO outputs 95 to 92 (software
  GPIO 173 to 170), the wrapper does the same.  They also appear on
  ``gpio_o``.  AXI ports have no ``ARESETN`` output either: a design
  resets its AXI logic from ``pl_reset_n_o``.

* ``m_axi_hpm0_fpd``, ``m_axi_hpm1_fpd``, ``m_axi_hpm0_lpd``: PS master
  ports (``MAXIGP0`` to ``MAXIGP2``), with configuration
  :vhdl:constant:`m_axi_config_c <nsl_xilinx.ps8.m_axi_config_c>`
  (40-bit address, 128-bit data, 16-bit ID, 256-beat bursts).
  ``*_clock_i`` is the port clock, supplied by the PL.

* ``s_axi_hpc0_fpd``, ``s_axi_hpc1_fpd``, ``s_axi_hp0_fpd`` to
  ``s_axi_hp3_fpd``, ``s_axi_lpd``: PL master ports into the PS
  (``SAXIGP0`` to ``SAXIGP6``, behind AFIFM0 to AFIFM6), with
  configuration ``s_axi_config_c`` (49-bit address, 128-bit data, 6-bit
  ID, 1-bit user).  ``*_level_o`` carries the AFI FIFO levels.  The
  primitive has separate read and write channel clocks, the wrapper
  feeds both from ``*_clock_i``.

* ``s_axi_acp_fpd``: accelerator coherency port (``SAXIACP``), with
  configuration ``s_axi_acp_config_c`` (40-bit address, 128-bit data,
  5-bit ID, 2-bit user).  The ACP only accepts aligned 16-byte single
  beats and 64-byte bursts, the wrapper does not check it.

* ``adma_*``, ``gdma_*``: flow control interfaces of the 8 channels of
  the LPD DMA and FPD DMA controllers, as
  :vhdl:type:`ps8_dma_fci_i_t <nsl_xilinx.ps8.ps8_dma_fci_i_t>` /
  :vhdl:type:`ps8_dma_fci_o_t <nsl_xilinx.ps8.ps8_dma_fci_o_t>`.  Each
  channel has its own clock input.

* ``pl_ps_irq_i``: PL to PS interrupts (GIC SPI 121 to 128, then 136
  to 143).  ``ps_pl_irq_lpd_o`` and ``ps_pl_irq_fpd_o``: PS peripheral
  interrupts, as the primitive exports them.

* ``spi0/1``, ``gem0..3``, ``uart0/1``, ``i2c0/1``, ``gpio``: EMIO
  routing of PS peripherals, see below.

Each AXI port has a configuration generic (``m_axi_hpm0_fpd_config_c``,
``s_axi_hp2_fpd_config_c``, ``s_axi_acp_fpd_config_c``, ...) setting
the configuration of its records, defaulting to the native one.  It may
differ from native only where conversion is trivial, elaboration fails
otherwise:

========================  ==========================  ======================
Field                     S_AXI (PL master)           M_AXI (PS master)
========================  ==========================  ======================
data width                32, 64 or 128               32, 64 or 128
address width             native or less,             native or less, MSBs
                          zero-extended               dropped
ID width                  native or less,             native or more,
                          zero-extended               zero-extended
max length                256 or less                 256
size, burst               optional                    mandatory
cache, qos, lock          optional                    optional
user                      native or less,             unused
                          zero-extended
========================  ==========================  ======================

Data width must match software configuration of the port, narrower
ports use data LSBs.  On M_AXI, a slave configuration without lock
answers exclusive accesses with ``OKAY``, which software sees as a
failed exclusive access.

Every unused input of the primitive is tied to the value Xilinx IP
gives it for a disabled interface, unused outputs are left open.

AXI mapping
===========

All PS8 AXI ports are AXI4, mapping is field by field.  ``AxUSER`` of
M_AXI ports is dropped, region reads 0.  On S_AXI ports, region is
dropped, ``user`` is ``AxUSER``.

EMIO peripherals
================

Software selects whether each peripheral is routed to MIO pins or to
EMIO.  EMIO ports of a peripheral routed to MIO carry nothing useful.

Tristate outputs of the primitive (``*TN``) are active high output
enables, despite their name.

SPI
---

SPI controllers are only supported as masters.  Each controller fans
out to ``spiN_slave_count_c`` (0 to 7) :vhdl:type:`spi_master_o
<nsl_spi.spi.spi_master_o>` / :vhdl:type:`spi_master_i
<nsl_spi.spi.spi_master_i>` pairs:

* ``sck`` is shared by all slaves,
* ``mosi`` is only enabled towards the selected slave,
* ``miso`` of the selected slave is fed back to the controller, ``'1'``
  when none is selected,
* ``cs_n`` is driven low for the selected slave.

With ``spiN_decoded_cs_c`` false, slave ``n`` is selected by the
controller's ``SSn`` output, at most 3 slaves.  With
``spiN_decoded_cs_c`` true, software must enable decoded chip selects,
the 3 SS outputs carry the index of the selected slave, ``"111"``
selecting none, at most 7 slaves.  Decoding is combinatorial: during a
change of selected slave, cs_n of a third slave may glitch.

Slave select input is tied high, so that the controller never sees a
mode fault.

GEM
---

* ``gemN_tx_clock_i`` is the GEM transmit clock when taken from EMIO,
  it is always exposed.
* ``gemN_gmii_tx_o`` and ``gemN_gmii_rx_i`` are
  :vhdl:type:`gmii_io_group_t <nsl_mii.gmii.gmii_io_group_t>` records.
* ``gemN_smi_o``/``gemN_smi_i`` are the MDIO master as
  :vhdl:type:`smi_master_o <nsl_smi.smi.smi_master_o>` /
  :vhdl:type:`smi_master_i <nsl_smi.smi.smi_master_i>`.
* ``gemN_ptp_tx_o``/``gemN_ptp_rx_o`` are the PTP event strobes of
  transmitted and received frames
  (:vhdl:type:`ps8_gem_ptp_strobes_t
  <nsl_xilinx.ps8.ps8_gem_ptp_strobes_t>`).
* ``gemN_tsu_inc_ctrl_i`` and ``gemN_tsu_timer_cmp_val_o`` are the GEM
  timer increment control input and timer comparison output.

The time stamp unit is shared by the four GEMs:

* ``gem_tsu_timer_o`` is the 94-bit TSU counter, synchronous to the
  TSU clock,
* ``gem_tsu_clock_i`` is the TSU clock when software selects EMIO as
  its source,
* ``gem_tsu_ps_clock_o``/``gem_tsu_ps_clock_i`` are the pair Xilinx IP
  exports when the TSU is enabled, for the design to close through the
  fabric.  ``gem_tsu_ps_clock_o`` goes through a ``BUFG_PS``.

UART
----

UARTs use :vhdl:type:`uart_signals_t <nsl_uart.uart.uart_signals_t>`
in both directions, the controller being a DTE: ``uartN_o.rts`` is
RTS, ``uartN_i.rts`` is CTS, etc.  Control signals are positive logic,
the wrapper inverts them to the controller's active-low ones.  Inputs
default to :vhdl:constant:`uart_dce_absent_c
<nsl_uart.uart.uart_dce_absent_c>`, so that hardware flow control
never stalls on an unconnected port.

I2C
---

I2C controllers map to :vhdl:type:`i2c_o <nsl_i2c.i2c.i2c_o>` /
:vhdl:type:`i2c_i <nsl_i2c.i2c.i2c_i>`.  A line is drained when the
controller enables its output driving low.

GPIO
----

The EMIO GPIO banks (banks 3 to 5, software GPIO 78 to 173) map to
``gpio_o(0 to 95)``, a :vhdl:type:`tristated_vector
<nsl_io.io.tristated_vector>`, and ``gpio_i(0 to 95)``.  Software reads
``gpio_i`` even for pins it drives.  ``gpio_o(92 to 95)`` also drive
``pl_reset_n_o``.

Register settings report
========================

Elaboration reports, as notes, the register fields the wrapper
configuration implies, for software to apply.  Both GHDL and Vivado
synthesis print them (Vivado as ``RTL assertion`` lines of the
synthesis log)::

  nsl_xilinx.ps8: write 0xFFD80118 mask 0x00800000 value 0x00800000 # PMU_GLOBAL.REQ_PWRUP_INT_EN.PL
  nsl_xilinx.ps8: write 0xFF419000 mask 0x00000300 value 0x00000000 # LPD_SLCR.AFI_FS, M_AXI_HPM0_LPD 32-bit
  nsl_xilinx.ps8: write 0xFD390000 mask 0x00000003 value 0x00000001 # AFIFM3.AFIFM_RDCTRL.FABRIC_WIDTH, 64-bit
  nsl_xilinx.ps8: pl clock 0 frequency 100000000 Hz

Reported fields are:

* PL power-up request (``PMU_GLOBAL.REQ_PWRUP_INT_EN`` and
  ``REQ_PWRUP_TRIG``, then polling ``REQ_PWRUP_STATUS``), always,
* data widths of M_AXI ports (``AFI_FS`` of FPD_SLCR and LPD_SLCR) and
  of S_AXI ports (``FABRIC_WIDTH`` of AFIFM0 to AFIFM6 ``RDCTRL`` and
  ``WRCTRL``), from the port configurations,
* PL clock frequencies, from ``pl_clock_frequency_c`` (0 for unused
  clocks, not reported).  The wrapper does not use them otherwise.

Settings depending on how EMIO peripherals are used (clock source
selection, MIO routing) cannot be seen from the wrapper and are not
reported.  ``report_registers_c => false`` silences the notes.

Clock domains and reset
=======================

Each AXI port record is synchronous to its ``*_clock_i``.  The DMA
flow control interface of channel ``n`` is synchronous to
``adma_clock_i(n)`` / ``gdma_clock_i(n)``.  AFI FIFO levels are
synchronous to the port clock.

``pl_reset_n_o`` is driven by software through GPIO, it is
asynchronous to every PL clock.

EMIO signals of SPI, UART, I2C and GPIO are not synchronous to any PL
clock.  GEM signals are synchronous to their GMII clocks, the TSU
counter to the TSU clock.

Verification limits
===================

The wrapper elaborates under GHDL with the ``PS8`` instance left
unbound; binding to the primitive, and the PS side, only exist in a
Vivado build.
