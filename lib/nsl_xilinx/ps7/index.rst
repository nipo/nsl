=====================
 Zynq-7000 PS wrapper
=====================

:vhdl:component:`ps7_wrapper <nsl_xilinx.ps7.ps7_wrapper>` is a plain
VHDL instantiation of the Zynq-7000 ``PS7`` primitive, without Vivado
block design nor processing_system7 IP.  It exposes the PL side of the
processing system as NSL records.

The wrapper source is only registered for Zynq-7000 parts
(``target_part`` matching ``xc7z*``).  There is no simulation model of
the processing system: the partition has no simulation implementation
of the wrapper.  The package and the write ID tracker are available
everywhere.

Configuration by software
=========================

The primitive has no configuration attribute: everything is set up by
software running on the PS (usually the first stage boot loader, from
``ps7_init``) before the PL ports work:

* FCLK clock sources, dividers and enables (``SLCR.FPGA*_CLK_CTRL``),
* PS-PL level shifters (``SLCR.LVL_SHFTR_EN``, 0xf for both
  directions),
* PL resets (``SLCR.FPGA_RST_CTRL``, which drives ``fclk_reset_n_o``),
* for the DMA controller peripheral interfaces, the DMAC security and
  peripheral settings (``SLCR.TZ_DMA_*``).

Until then, AXI ports behave as if disconnected: a design must not
expect handshakes from the PS before software ran.

Dedicated pins
==============

MIO, DDR, ``PS_CLK``, ``PS_PORB`` and ``PS_SRSTB`` are dedicated pins
of the PS: they are left unconnected in the wrapper, Vivado places
them without PL routing.  If a flow later requires them as top-level
ports, they would need to be added.

Interfaces
==========

* ``fclk_o``, ``fclk_reset_n_o``: the four PL clocks and their reset
  outputs.  No global buffer is inserted.

* ``m_axi_gp0/1``: PS master ports (``M_AXI_GP``), AXI3, seen as
  AXI4 with configuration :vhdl:constant:`m_axi_gp_config_c
  <nsl_xilinx.ps7.m_axi_gp_config_c>` (32-bit address and data, 12-bit
  ID, 16-beat bursts).  ``*_clock_i`` is the port clock, supplied by
  the PL, ``*_reset_n_o`` its ``ARESETN`` output.

* ``s_axi_gp0/1``: PL master ports into the PS (``S_AXI_GP``), with
  configuration ``s_axi_gp_config_c`` (6-bit ID).

* ``s_axi_hp0..3``: high performance PL master ports into the PS
  memory, through the AFI (``S_AXI_HP``), with configuration
  ``s_axi_hp_config_c`` (64-bit data, 6-bit ID).  ``*_level_o``
  carries the AFI FIFO levels, ``*_read/write_issue_cap1_i`` select
  the alternate issuing capability software programmed in the AFI.

* ``s_axi_acp``: accelerator coherency port (``S_AXI_ACP``), with
  configuration ``s_axi_acp_config_c`` (64-bit data, 3-bit ID, 5-bit
  user).

* ``dmac_*``: DMA controller (DMA-330) peripheral request interfaces 0
  to 3, the ones routed to the PL, with the
  :vhdl:type:`peripheral_t <nsl_amba.dma_request.peripheral_t>` /
  :vhdl:type:`dmac_t <nsl_amba.dma_request.dmac_t>` records.  Each
  interface has its own clock input and ``DMAn_RSTN`` reset output.

* ``dmac_irq_o(n)``: DMA controller event interrupts, ``IRQP2F(20+n)``;
  ``dmac_irq_abort_o``: DMA controller abort interrupt, ``IRQP2F(28)``.

* ``irq_f2p_i``: PL to PS interrupts (GIC IDs 61 to 68, then 84 to 91).

* ``spi0/1``, ``gem0/1``, ``uart0/1``, ``i2c0/1``, ``gpio``: EMIO
  routing of PS peripherals, see below.

Each AXI port has a configuration generic (``m_axi_gp0_config_c``,
``s_axi_hp2_config_c``, ``s_axi_acp_config_c``, ...) setting the
configuration of its records, defaulting to the native one.  It may
differ from native only where conversion is trivial, elaboration fails
otherwise:

========================  ==========================  ======================
Field                     S_AXI (PL master)           M_AXI (PS master)
========================  ==========================  ======================
data width                native (32 or 64 on HP)     native
address width             32 or less, zero-extended   32 or less, MSBs
                                                      dropped
ID width                  native or less,             native or more,
                          zero-extended               zero-extended
max length                16 or less                  16 or more
size, burst               optional                    mandatory
cache, qos, lock          optional                    optional
user                      5 or less on ACP, ignored   unused
                          elsewhere
========================  ==========================  ======================

On M_AXI, a slave configuration without lock answers exclusive
accesses with ``OKAY``, which software sees as a failed exclusive
access.  S_AXI_HP data width must match software configuration of the
AFI (32-bit mode uses the data LSBs).

Every unused input of the primitive is tied to its inactive value (as
the Xilinx IP does for a disabled interface), unused outputs are left
open.

AXI3 to AXI4 mapping
====================

M_AXI_GP (PS master)
--------------------

* ``AxLEN`` (4 bits) is ``len_m1``, ``AxSIZE`` (2 bits) is
  zero-extended to ``size_l2``.
* ``AxLOCK(0)`` (exclusive) is ``lock``.  ``AxLOCK(1)`` (locked
  transfer, which AXI4 removed) is dropped; the GP ports never issue
  it.
* ``WID`` is dropped: the GP master ports issue write data in write
  address order, which is the AXI4 rule.
* ``AxBURST``, ``AxCACHE``, ``AxPROT`` and ``AxQOS`` are mapped as
  is.  Region reads 0.

S_AXI_GP, S_AXI_HP, S_AXI_ACP (PL master)
-----------------------------------------

* ``len_m1`` is truncated to 4-bit ``AxLEN``: masters must not issue
  bursts longer than 16 beats.  ``AxSIZE`` is the 2 LSBs of
  ``size_l2``.
* ``AxLOCK`` is ``'0' & lock``.
* ``WID`` is generated by :vhdl:component:`ps7_axi3_wid_tracker
  <nsl_xilinx.ps7.ps7_axi3_wid_tracker>`: accepted AW IDs are queued,
  up to 8, and each write data burst
  carries the ID of the oldest outstanding write, popped on its
  ``WLAST`` handshake.  This is exact because AXI4 write data is in
  write address order.  With no queued ID, a burst carries the ID of
  the AW the master presents, so W never waits for ``AWREADY``, as
  AXI dependency rules require.  One burst may complete before its
  AW handshake; the next one is held until that handshake.  W is also
  held while the master presents no AW and no ID is queued.  AW is
  held while the queue is full.
* On ACP, ``user`` is ``AxUSER``, zero-extended.  Region and user on
  other ports are dropped.

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
``spiN_decoded_cs_c`` true, software must enable decoded chip selects
(``PERI_SEL``, ``is-decoded-cs`` in Linux device tree), the 3 SS
outputs carry the index of the selected slave, ``"111"`` selecting
none, at most 7 slaves.  Decoding is combinatorial: during a change of
selected slave, cs_n of a third slave may glitch.

Slave select input is tied high, so that the controller never sees a
mode fault.

GEM
---

* ``gemN_tx_clock_i`` is the GEM transmit clock.  The GEM takes it
  from EMIO whenever its TX clock is selected from EMIO in
  ``SLCR.GEMn_CLK_CTRL``, independently of GMII routing, so it is
  always exposed.
* ``gemN_gmii_tx_o`` and ``gemN_gmii_rx_i`` are
  :vhdl:type:`gmii_io_group_t <nsl_mii.gmii.gmii_io_group_t>` records,
  matching :vhdl:component:`gmii_z7_phy <nsl_mii.gmii.gmii_z7_phy>`.
* ``gemN_smi_o``/``gemN_smi_i`` are the MDIO master as
  :vhdl:type:`smi_master_o <nsl_smi.smi.smi_master_o>` /
  :vhdl:type:`smi_master_i <nsl_smi.smi.smi_master_i>`.
* ``gemN_ptp_tx_o``/``gemN_ptp_rx_o`` are the PTP event strobes of
  transmitted and received frames
  (:vhdl:type:`ps7_gem_ptp_strobes_t
  <nsl_xilinx.ps7.ps7_gem_ptp_strobes_t>`).  The Zynq-7000 GEM does
  not export its timestamp counter.

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

The EMIO GPIO bank (banks 2 and 3, software GPIO 54 to 117) maps to
``gpio_o(0 to 63)``, a :vhdl:type:`tristated_vector
<nsl_io.io.tristated_vector>`, and ``gpio_i(0 to 63)``.  Software reads
``gpio_i`` even for pins it drives.

Register settings report
========================

Elaboration reports, as notes, the SLCR and AFI register fields the
wrapper configuration implies, for software to apply.  Both GHDL and
Vivado synthesis print them (Vivado as ``RTL assertion`` lines of the
synthesis log)::

  nsl_xilinx.ps7: write 0xF8000900 mask 0x0000000F value 0x0000000F # LVL_SHFTR_EN, PS-PL level shifters enabled
  nsl_xilinx.ps7: write 0xF8009000 mask 0x00000001 value 0x00000001 # AFI1_RDCHAN_CTRL.32BitEn, S_AXI_HP1 32-bit
  nsl_xilinx.ps7: fclk 0 frequency 100000000 Hz

Reported fields are:

* ``LVL_SHFTR_EN``, always,
* ``32BitEn`` of ``AFIn_RDCHAN_CTRL`` and ``AFIn_WRCHAN_CTRL``, from
  the data width of ``s_axi_hpN_config_c``,
* FCLK frequencies, from ``fclk_frequency_c`` (0 for unused clocks,
  not reported).  The wrapper does not use them otherwise.

Settings depending on how EMIO peripherals are used (clock source
selection, MIO routing) cannot be seen from the wrapper and are not
reported.  ``report_registers_c => false`` silences the notes.

Clock domains and reset
=======================

Each AXI port record is synchronous to its ``*_clock_i``.  The write
ID tracker of an S_AXI port is reset by the port's ``ARESETN``
output.  The DMA peripheral interface ``n`` is synchronous to
``dmac_clock_i(n)``.  S_AXI_HP FIFO levels and issuing capability
selects are synchronous to the port clock.

EMIO signals of SPI, UART, I2C and GPIO are not synchronous to any PL
clock.  GEM signals are synchronous to their GMII clocks.

Verification limits
===================

The wrapper elaborates under GHDL with the ``PS7`` instance left
unbound; binding to the primitive, and the PS side, only exist in a
Vivado build.
