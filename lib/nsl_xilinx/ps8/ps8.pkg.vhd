library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_spi, nsl_mii, nsl_smi, nsl_uart, nsl_i2c, nsl_io;

-- Zynq UltraScale+ MPSoC processing system (PS8) seen from the
-- programmable logic.
package ps8 is

  -- All PS8 AXI ports are AXI4.  They map to NSL records field by
  -- field: AxLEN is 8 bits wide, AxLOCK is a single bit (normal or
  -- exclusive), there is no WID.

  -- M_AXI_HPM0_FPD, M_AXI_HPM1_FPD and M_AXI_HPM0_LPD (PS is master, PL
  -- is slave).  The port is 128-bit wide unless software selected a
  -- narrower width (FPD_SLCR.AFI_FS, LPD_SLCR.AFI_FS), where it uses
  -- data LSBs.  AxUSER is dropped, region reads 0.
  constant m_axi_config_c : nsl_amba.axi4_mm.config_t
    := nsl_amba.axi4_mm.config(address_width => 40, data_bus_width => 128,
                               id_width => 16, max_length => 256, size => true, burst => true,
                               cache => true, lock => true, qos => true);

  -- S_AXI_HPC0_FPD, S_AXI_HPC1_FPD, S_AXI_HP0_FPD to S_AXI_HP3_FPD and
  -- S_AXI_LPD (PL is master, PS is slave through an AFI FIFO).  The
  -- port is 128-bit wide unless software selected a narrower width
  -- (AFIFM RDCTRL/WRCTRL), where it uses data LSBs.  user maps to
  -- AxUSER.  Region is dropped.
  constant s_axi_config_c : nsl_amba.axi4_mm.config_t
    := nsl_amba.axi4_mm.config(address_width => 49, data_bus_width => 128,
                               user_width => 1, id_width => 6, max_length => 256,
                               size => true, burst => true,
                               cache => true, lock => true, qos => true);

  -- S_AXI_ACP_FPD (PL is master, PS is slave through the APU
  -- accelerator coherency port).  user maps to AxUSER.  The ACP only
  -- accepts 16-byte single beats and 64-byte bursts, aligned (see
  -- UG1085), the wrapper does not check it.
  constant s_axi_acp_config_c : nsl_amba.axi4_mm.config_t
    := nsl_amba.axi4_mm.config(address_width => 40, data_bus_width => 128,
                               user_width => 2, id_width => 5, max_length => 256,
                               size => true, burst => true,
                               cache => true, lock => true, qos => true);

  -- An M_AXI port without slave: never accepts anything.
  constant m_axi_slave_idle_c : nsl_amba.axi4_mm.slave_t := (
    aw => nsl_amba.axi4_mm.handshake_defaults(m_axi_config_c),
    w => nsl_amba.axi4_mm.handshake_defaults(m_axi_config_c),
    b => nsl_amba.axi4_mm.write_response_defaults(m_axi_config_c),
    ar => nsl_amba.axi4_mm.handshake_defaults(m_axi_config_c),
    r => nsl_amba.axi4_mm.read_data_defaults(m_axi_config_c)
    );

  -- An S_AXI port without master: never issues anything.
  constant s_axi_master_idle_c : nsl_amba.axi4_mm.master_t := (
    aw => nsl_amba.axi4_mm.address_defaults(s_axi_config_c),
    w => nsl_amba.axi4_mm.write_data_defaults(s_axi_config_c),
    b => nsl_amba.axi4_mm.handshake_defaults(s_axi_config_c),
    ar => nsl_amba.axi4_mm.address_defaults(s_axi_config_c),
    r => nsl_amba.axi4_mm.handshake_defaults(s_axi_config_c)
    );

  -- An S_AXI_ACP port without master: never issues anything.
  constant s_axi_acp_master_idle_c : nsl_amba.axi4_mm.master_t := (
    aw => nsl_amba.axi4_mm.address_defaults(s_axi_acp_config_c),
    w => nsl_amba.axi4_mm.write_data_defaults(s_axi_acp_config_c),
    b => nsl_amba.axi4_mm.handshake_defaults(s_axi_acp_config_c),
    ar => nsl_amba.axi4_mm.address_defaults(s_axi_acp_config_c),
    r => nsl_amba.axi4_mm.handshake_defaults(s_axi_acp_config_c)
    );

  -- Frequency of each PL clock, in Hz, 0 for an unused one.
  type ps8_pl_clock_frequency_vector is array (0 to 3) of natural;

  -- AFI FIFO levels of an S_AXI port (not ACP)
  type ps8_afi_level_t is
  record
    -- RCOUNT, read data
    read_data : unsigned(7 downto 0);
    -- WCOUNT, write data
    write_data : unsigned(7 downto 0);
    -- RACOUNT, read commands
    read_command : unsigned(3 downto 0);
    -- WACOUNT, write commands
    write_command : unsigned(3 downto 0);
  end record;

  -- Precision time protocol event strobes of a GEM, in the GMII clock
  -- domain of their direction.
  type ps8_gem_ptp_strobes_t is
  record
    -- Start of frame
    sof : std_ulogic;
    sync : std_ulogic;
    delay_req : std_ulogic;
    pdelay_req : std_ulogic;
    pdelay_resp : std_ulogic;
  end record;

  -- DMA controller (LPD DMA or FPD DMA) flow control interface of a
  -- channel, PL side to the DMA.  Names are the UG1085 ones:
  -- cvld/cack is the PL flow control request handshake, tvld/tack the
  -- DMA transfer notification handshake.
  type ps8_dma_fci_i_t is
  record
    -- PL2xDMACVLD
    cvld : std_ulogic;
    -- PL2xDMATACK
    tack : std_ulogic;
  end record;

  -- DMA to PL side of a channel flow control interface.
  type ps8_dma_fci_o_t is
  record
    -- xDMA2PLCACK
    cack : std_ulogic;
    -- xDMA2PLTVLD
    tvld : std_ulogic;
  end record;

  type ps8_dma_fci_i_vector is array (natural range <>) of ps8_dma_fci_i_t;
  type ps8_dma_fci_o_vector is array (natural range <>) of ps8_dma_fci_o_t;

  constant ps8_dma_fci_idle_c : ps8_dma_fci_i_t := (cvld => '0', tack => '0');

  -- Plain instantiation of the PS8 primitive, without Vivado block
  -- design.  Only available for Zynq UltraScale+ parts (target_part
  -- xczu* and xck*), there is no simulation model.
  --
  -- MIO, DDR, PS-GTR and other PS dedicated pins are left unconnected:
  -- they need no PL routing.
  --
  -- The PL side of the PS is only functional once software configured
  -- it: PL power-up and isolation removal (PMU_GLOBAL.REQ_PWRUP), PL
  -- clocks (CRL_APB.PLn_REF_CTRL), AXI port data widths, and PL resets
  -- (EMIO GPIO bank 5).  The primitive has no configuration attribute.
  --
  -- pl_clock_o: PL_CLK0..3, through a BUFG_PS each (the PS8 clock
  -- outputs can only reach the fabric through one).
  -- pl_clock_frequency_c is the frequency software is expected to set
  -- for each of them.  The wrapper does not use it, it is reported for
  -- derivation of software settings and constraints.
  --
  -- pl_reset_n_o: PL resets 0..3, EMIO GPIO outputs 95 to 92, as Xilinx
  -- IP maps them.  They are also visible on gpio_o(95 downto 92).  The
  -- PS has no other reset towards the PL: AXI ports have no ARESETN.
  --
  -- With report_registers_c, elaboration reports the register fields
  -- the configuration implies, one note per field:
  --
  --   nsl_xilinx.ps8: write 0x<address> mask 0x<mask> value 0x<value> # <comment>
  --   nsl_xilinx.ps8: pl clock <n> frequency <hz> Hz
  --
  -- Fields depending on how EMIO ports are used are not reported:
  -- usage is invisible from the wrapper.
  --
  -- *_config_c: configuration of each AXI port records, defaulting to
  -- the native one.  Elaboration fails unless conversion from/to
  -- native is trivial:
  -- * data width is 32, 64 or 128, it must match software
  --   configuration of the port;
  -- * address width is native or less.  It is zero-extended towards
  --   the PS, M_AXI ports drop the PS address MSBs;
  -- * on M_AXI ports, ID width and max_length may be larger than
  --   native (IDs are zero-extended), size and burst are mandatory;
  -- * on S_AXI ports, ID width, max_length and user width may be
  --   smaller than native (zero-extended);
  -- * cache, qos and lock may be absent.  Absent lock on M_AXI makes
  --   exclusive accesses get OKAY, software sees them fail.
  --
  -- *_clock_i: clock of the matching AXI port, the port's records are
  -- synchronous to it.  On S_AXI ports, it clocks both read and write
  -- channels.
  --
  -- s_axi_*_level_o: AFI FIFO levels of the port, in its clock domain.
  --
  -- adma_*/gdma_*: flow control interfaces of the 8 channels of LPD
  -- DMA (ADMA) and FPD DMA (GDMA), channel n in *_clock_i(n) domain.
  --
  -- pl_ps_irq_i(n): PL to PS interrupt, PL_PS_IRQ0(n) for n < 8 (GIC
  -- SPI 121 to 128), PL_PS_IRQ1(n-8) for n >= 8 (GIC SPI 136 to 143).
  -- ps_pl_irq_lpd_o/ps_pl_irq_fpd_o: PS peripheral interrupts towards
  -- the PL, see UG1085 for the mapping.
  --
  -- The following ports are EMIO routing of PS peripherals.  They only
  -- carry signals for peripherals software routed to EMIO.  Inputs
  -- default to an idle peer.
  --
  -- spiN_o/spiN_i: SPI controller N as a master, fanned out to
  -- spiN_slave_count_c slaves.  sck is shared, mosi is only enabled
  -- towards the selected slave, miso of the selected slave is fed back
  -- ('1' when none is selected).  Without spiN_decoded_cs_c, slave n
  -- is selected by SSn (up to 3 slaves).  With spiN_decoded_cs_c, the
  -- controller is expected in decoded chip select mode and the 3 SS
  -- outputs carry the binary index of the selected slave (up to 7
  -- slaves, "111" selects none).  Decoding is combinatorial, it may
  -- glitch other slaves' cs_n during transitions.
  --
  -- gemN_*: GEM N.  gemN_tx_clock_i is the GMII TX clock the GEM runs
  -- its transmitter from when its clock is taken from EMIO, it is
  -- exposed regardless of GMII routing.  gemN_gmii_tx_o and
  -- gemN_ptp_tx_o are synchronous to it.  gemN_gmii_rx_i, col, crs and
  -- gemN_ptp_rx_o are synchronous to gemN_gmii_rx_clock_i.  gemN_smi_*
  -- is the MDIO master.  gemN_ext_int_i is the GEM external interrupt
  -- input.  gemN_tsu_inc_ctrl_i is the GEM timer increment control
  -- input, gemN_tsu_timer_cmp_val_o the GEM timer comparison output.
  --
  -- gem_tsu_clock_i: GEM time stamp unit clock, when software selects
  -- EMIO as its source (EMIO_ENET_TSU_CLK).  gem_tsu_ps_clock_o and
  -- gem_tsu_ps_clock_i are the FMIO_GEM_TSU_CLK_TO_PL_BUFG /
  -- FMIO_GEM_TSU_CLK_FROM_PL pair Xilinx IP exports when the TSU is
  -- enabled, for the design to close through the fabric;
  -- gem_tsu_ps_clock_o goes through a BUFG_PS.  gem_tsu_timer_o: value
  -- of the time stamp unit counter, synchronous to the TSU clock.
  --
  -- uartN_o/uartN_i: UART N, as a DTE.  uartN_o.dcd and .ri are always
  -- deasserted.  Inputs default to a DCE that is always ready.
  --
  -- i2cN_o/i2cN_i: I2C controller N.
  --
  -- gpio_o/gpio_i: EMIO GPIO banks 3 to 5, gpio_o(n)/gpio_i(n) are
  -- software GPIO 78+n.  gpio_i is read by software regardless of
  -- gpio_o(n).en.
  component ps8_wrapper is
    generic(
      m_axi_hpm0_fpd_config_c : nsl_amba.axi4_mm.config_t := m_axi_config_c;
      m_axi_hpm1_fpd_config_c : nsl_amba.axi4_mm.config_t := m_axi_config_c;
      m_axi_hpm0_lpd_config_c : nsl_amba.axi4_mm.config_t := m_axi_config_c;
      s_axi_hpc0_fpd_config_c : nsl_amba.axi4_mm.config_t := s_axi_config_c;
      s_axi_hpc1_fpd_config_c : nsl_amba.axi4_mm.config_t := s_axi_config_c;
      s_axi_hp0_fpd_config_c : nsl_amba.axi4_mm.config_t := s_axi_config_c;
      s_axi_hp1_fpd_config_c : nsl_amba.axi4_mm.config_t := s_axi_config_c;
      s_axi_hp2_fpd_config_c : nsl_amba.axi4_mm.config_t := s_axi_config_c;
      s_axi_hp3_fpd_config_c : nsl_amba.axi4_mm.config_t := s_axi_config_c;
      s_axi_lpd_config_c : nsl_amba.axi4_mm.config_t := s_axi_config_c;
      s_axi_acp_fpd_config_c : nsl_amba.axi4_mm.config_t := s_axi_acp_config_c;

      spi0_decoded_cs_c : boolean := false;
      spi0_slave_count_c : natural range 0 to 7 := 0;
      spi1_decoded_cs_c : boolean := false;
      spi1_slave_count_c : natural range 0 to 7 := 0;

      pl_clock_frequency_c : ps8_pl_clock_frequency_vector := (others => 0);
      report_registers_c : boolean := true
      );
    port(
      pl_clock_o : out std_ulogic_vector(0 to 3);
      pl_reset_n_o : out std_ulogic_vector(0 to 3);

      m_axi_hpm0_fpd_clock_i : in std_ulogic := '0';
      m_axi_hpm0_fpd_o : out nsl_amba.axi4_mm.master_t;
      m_axi_hpm0_fpd_i : in nsl_amba.axi4_mm.slave_t := m_axi_slave_idle_c;

      m_axi_hpm1_fpd_clock_i : in std_ulogic := '0';
      m_axi_hpm1_fpd_o : out nsl_amba.axi4_mm.master_t;
      m_axi_hpm1_fpd_i : in nsl_amba.axi4_mm.slave_t := m_axi_slave_idle_c;

      m_axi_hpm0_lpd_clock_i : in std_ulogic := '0';
      m_axi_hpm0_lpd_o : out nsl_amba.axi4_mm.master_t;
      m_axi_hpm0_lpd_i : in nsl_amba.axi4_mm.slave_t := m_axi_slave_idle_c;

      s_axi_hpc0_fpd_clock_i : in std_ulogic := '0';
      s_axi_hpc0_fpd_i : in nsl_amba.axi4_mm.master_t := s_axi_master_idle_c;
      s_axi_hpc0_fpd_o : out nsl_amba.axi4_mm.slave_t;
      s_axi_hpc0_fpd_level_o : out ps8_afi_level_t;

      s_axi_hpc1_fpd_clock_i : in std_ulogic := '0';
      s_axi_hpc1_fpd_i : in nsl_amba.axi4_mm.master_t := s_axi_master_idle_c;
      s_axi_hpc1_fpd_o : out nsl_amba.axi4_mm.slave_t;
      s_axi_hpc1_fpd_level_o : out ps8_afi_level_t;

      s_axi_hp0_fpd_clock_i : in std_ulogic := '0';
      s_axi_hp0_fpd_i : in nsl_amba.axi4_mm.master_t := s_axi_master_idle_c;
      s_axi_hp0_fpd_o : out nsl_amba.axi4_mm.slave_t;
      s_axi_hp0_fpd_level_o : out ps8_afi_level_t;

      s_axi_hp1_fpd_clock_i : in std_ulogic := '0';
      s_axi_hp1_fpd_i : in nsl_amba.axi4_mm.master_t := s_axi_master_idle_c;
      s_axi_hp1_fpd_o : out nsl_amba.axi4_mm.slave_t;
      s_axi_hp1_fpd_level_o : out ps8_afi_level_t;

      s_axi_hp2_fpd_clock_i : in std_ulogic := '0';
      s_axi_hp2_fpd_i : in nsl_amba.axi4_mm.master_t := s_axi_master_idle_c;
      s_axi_hp2_fpd_o : out nsl_amba.axi4_mm.slave_t;
      s_axi_hp2_fpd_level_o : out ps8_afi_level_t;

      s_axi_hp3_fpd_clock_i : in std_ulogic := '0';
      s_axi_hp3_fpd_i : in nsl_amba.axi4_mm.master_t := s_axi_master_idle_c;
      s_axi_hp3_fpd_o : out nsl_amba.axi4_mm.slave_t;
      s_axi_hp3_fpd_level_o : out ps8_afi_level_t;

      s_axi_lpd_clock_i : in std_ulogic := '0';
      s_axi_lpd_i : in nsl_amba.axi4_mm.master_t := s_axi_master_idle_c;
      s_axi_lpd_o : out nsl_amba.axi4_mm.slave_t;
      s_axi_lpd_level_o : out ps8_afi_level_t;

      s_axi_acp_fpd_clock_i : in std_ulogic := '0';
      s_axi_acp_fpd_i : in nsl_amba.axi4_mm.master_t := s_axi_acp_master_idle_c;
      s_axi_acp_fpd_o : out nsl_amba.axi4_mm.slave_t;

      adma_clock_i : in std_ulogic_vector(0 to 7) := (others => '0');
      adma_i : in ps8_dma_fci_i_vector(0 to 7) := (others => ps8_dma_fci_idle_c);
      adma_o : out ps8_dma_fci_o_vector(0 to 7);
      gdma_clock_i : in std_ulogic_vector(0 to 7) := (others => '0');
      gdma_i : in ps8_dma_fci_i_vector(0 to 7) := (others => ps8_dma_fci_idle_c);
      gdma_o : out ps8_dma_fci_o_vector(0 to 7);

      pl_ps_irq_i : in std_ulogic_vector(0 to 15) := (others => '0');
      ps_pl_irq_lpd_o : out std_ulogic_vector(0 to 99);
      ps_pl_irq_fpd_o : out std_ulogic_vector(0 to 63);

      spi0_o : out nsl_spi.spi.spi_master_o_vector(0 to spi0_slave_count_c-1);
      spi0_i : in nsl_spi.spi.spi_master_i_vector(0 to spi0_slave_count_c-1)
        := (others => nsl_spi.spi.spi_master_i_idle_c);
      spi1_o : out nsl_spi.spi.spi_master_o_vector(0 to spi1_slave_count_c-1);
      spi1_i : in nsl_spi.spi.spi_master_i_vector(0 to spi1_slave_count_c-1)
        := (others => nsl_spi.spi.spi_master_i_idle_c);

      gem0_tx_clock_i : in std_ulogic := '0';
      gem0_gmii_tx_o : out nsl_mii.gmii.gmii_io_group_t;
      gem0_gmii_rx_clock_i : in std_ulogic := '0';
      gem0_gmii_rx_i : in nsl_mii.gmii.gmii_io_group_t := nsl_mii.gmii.gmii_io_group_idle_c;
      gem0_gmii_col_i : in std_ulogic := '0';
      gem0_gmii_crs_i : in std_ulogic := '0';
      gem0_smi_o : out nsl_smi.smi.smi_master_o;
      gem0_smi_i : in nsl_smi.smi.smi_master_i := nsl_smi.smi.smi_master_i_idle_c;
      gem0_ptp_tx_o : out ps8_gem_ptp_strobes_t;
      gem0_ptp_rx_o : out ps8_gem_ptp_strobes_t;
      gem0_ext_int_i : in std_ulogic := '0';
      gem0_tsu_inc_ctrl_i : in std_ulogic_vector(1 downto 0) := "00";
      gem0_tsu_timer_cmp_val_o : out std_ulogic;

      gem1_tx_clock_i : in std_ulogic := '0';
      gem1_gmii_tx_o : out nsl_mii.gmii.gmii_io_group_t;
      gem1_gmii_rx_clock_i : in std_ulogic := '0';
      gem1_gmii_rx_i : in nsl_mii.gmii.gmii_io_group_t := nsl_mii.gmii.gmii_io_group_idle_c;
      gem1_gmii_col_i : in std_ulogic := '0';
      gem1_gmii_crs_i : in std_ulogic := '0';
      gem1_smi_o : out nsl_smi.smi.smi_master_o;
      gem1_smi_i : in nsl_smi.smi.smi_master_i := nsl_smi.smi.smi_master_i_idle_c;
      gem1_ptp_tx_o : out ps8_gem_ptp_strobes_t;
      gem1_ptp_rx_o : out ps8_gem_ptp_strobes_t;
      gem1_ext_int_i : in std_ulogic := '0';
      gem1_tsu_inc_ctrl_i : in std_ulogic_vector(1 downto 0) := "00";
      gem1_tsu_timer_cmp_val_o : out std_ulogic;

      gem2_tx_clock_i : in std_ulogic := '0';
      gem2_gmii_tx_o : out nsl_mii.gmii.gmii_io_group_t;
      gem2_gmii_rx_clock_i : in std_ulogic := '0';
      gem2_gmii_rx_i : in nsl_mii.gmii.gmii_io_group_t := nsl_mii.gmii.gmii_io_group_idle_c;
      gem2_gmii_col_i : in std_ulogic := '0';
      gem2_gmii_crs_i : in std_ulogic := '0';
      gem2_smi_o : out nsl_smi.smi.smi_master_o;
      gem2_smi_i : in nsl_smi.smi.smi_master_i := nsl_smi.smi.smi_master_i_idle_c;
      gem2_ptp_tx_o : out ps8_gem_ptp_strobes_t;
      gem2_ptp_rx_o : out ps8_gem_ptp_strobes_t;
      gem2_ext_int_i : in std_ulogic := '0';
      gem2_tsu_inc_ctrl_i : in std_ulogic_vector(1 downto 0) := "00";
      gem2_tsu_timer_cmp_val_o : out std_ulogic;

      gem3_tx_clock_i : in std_ulogic := '0';
      gem3_gmii_tx_o : out nsl_mii.gmii.gmii_io_group_t;
      gem3_gmii_rx_clock_i : in std_ulogic := '0';
      gem3_gmii_rx_i : in nsl_mii.gmii.gmii_io_group_t := nsl_mii.gmii.gmii_io_group_idle_c;
      gem3_gmii_col_i : in std_ulogic := '0';
      gem3_gmii_crs_i : in std_ulogic := '0';
      gem3_smi_o : out nsl_smi.smi.smi_master_o;
      gem3_smi_i : in nsl_smi.smi.smi_master_i := nsl_smi.smi.smi_master_i_idle_c;
      gem3_ptp_tx_o : out ps8_gem_ptp_strobes_t;
      gem3_ptp_rx_o : out ps8_gem_ptp_strobes_t;
      gem3_ext_int_i : in std_ulogic := '0';
      gem3_tsu_inc_ctrl_i : in std_ulogic_vector(1 downto 0) := "00";
      gem3_tsu_timer_cmp_val_o : out std_ulogic;

      gem_tsu_clock_i : in std_ulogic := '0';
      gem_tsu_ps_clock_o : out std_ulogic;
      gem_tsu_ps_clock_i : in std_ulogic := '0';
      gem_tsu_timer_o : out unsigned(93 downto 0);

      uart0_o : out nsl_uart.uart.uart_signals_t;
      uart0_i : in nsl_uart.uart.uart_signals_t := nsl_uart.uart.uart_dce_absent_c;
      uart1_o : out nsl_uart.uart.uart_signals_t;
      uart1_i : in nsl_uart.uart.uart_signals_t := nsl_uart.uart.uart_dce_absent_c;

      i2c0_o : out nsl_i2c.i2c.i2c_o;
      i2c0_i : in nsl_i2c.i2c.i2c_i := nsl_i2c.i2c.i2c_i_idle_c;
      i2c1_o : out nsl_i2c.i2c.i2c_o;
      i2c1_i : in nsl_i2c.i2c.i2c_i := nsl_i2c.i2c.i2c_i_idle_c;

      gpio_o : out nsl_io.io.tristated_vector(0 to 95);
      gpio_i : in std_ulogic_vector(0 to 95) := (others => '0')
      );
  end component;

end package;
