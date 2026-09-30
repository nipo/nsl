library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_spi, nsl_mii, nsl_smi, nsl_uart, nsl_i2c, nsl_io;

-- Zynq-7000 processing system (PS7) seen from the programmable logic.
package ps7 is

  -- AXI3 general purpose ports seen as NSL AXI4-MM records.
  --
  -- M_AXI_GP (PS is master, PL is slave), AXI3 to AXI4:
  -- * AxLEN is 4 bits wide, it maps to len_m1 as is (bursts of up to
  --   16 beats);
  -- * AxSIZE is 2 bits wide, it is zero-extended;
  -- * AxLOCK(0) (exclusive access) maps to lock, AxLOCK(1) (locked
  --   access, absent from AXI4) is dropped.  The GP master ports never
  --   issue locked accesses;
  -- * WID is dropped: GP master ports issue write data in write
  --   address order, which is the AXI4 write data ordering;
  -- * AxBURST, AxCACHE, AxPROT and AxQOS map as is.  AxCACHE is passed
  --   as the PS drives it, without the modifiable bit override Xilinx
  --   IP offers as an option;
  -- * region is not driven by the PS, it reads 0.
  constant m_axi_gp_config_c : nsl_amba.axi4_mm.config_t
    := nsl_amba.axi4_mm.config(address_width => 32, data_bus_width => 32,
                               id_width => 12, max_length => 16, size => true, burst => true,
                               cache => true, lock => true, qos => true);

  -- S_AXI_GP (PL is master, PS is slave), AXI4 to AXI3:
  -- * len_m1 maps to 4-bit AxLEN.  A master must not issue bursts
  --   longer than 16 beats;
  -- * AxSIZE is the two LSBs of size_l2: a size of 8 bytes or more is
  --   illegal on this 32-bit bus anyway;
  -- * AxLOCK is '0' & lock (normal or exclusive, never locked);
  -- * WID is generated: accepted AW IDs are queued (up to
  --   ps7_s_axi_gp_write_acceptance_c of them, the write acceptance
  --   of the port) and each write data burst carries the ID of the
  --   oldest queued write.  This is exact because AXI4 write data
  --   comes in write address order.  With the queue empty, a burst
  --   carries the ID of the AW the master presents, so W never waits
  --   for the PS AWREADY.  W beats are held only while the master
  --   presents no AW, or while the AW of a burst already completed
  --   is not handshaken.  AW is held while the queue is full;
  -- * region and user are dropped.
  constant s_axi_gp_config_c : nsl_amba.axi4_mm.config_t
    := nsl_amba.axi4_mm.config(address_width => 32, data_bus_width => 32,
                               id_width => 6, max_length => 16, size => true, burst => true,
                               cache => true, lock => true, qos => true);

  constant ps7_s_axi_gp_write_acceptance_c : positive := 8;

  -- S_AXI_HP (PL is master, PS is slave through the AFI), AXI4 to
  -- AXI3, mapped as S_AXI_GP.  The port is 64-bit wide unless software
  -- enabled its 32-bit mode (AFI 32BitEn), where it uses data LSBs.
  constant s_axi_hp_config_c : nsl_amba.axi4_mm.config_t
    := nsl_amba.axi4_mm.config(address_width => 32, data_bus_width => 64,
                               id_width => 6, max_length => 16, size => true, burst => true,
                               cache => true, lock => true, qos => true);

  -- AFI write acceptance is 8 to 32 commands depending on burst
  -- length, WID tracking covers the guaranteed minimum.
  constant ps7_s_axi_hp_write_acceptance_c : positive := 8;

  -- S_AXI_ACP (PL is master, PS is slave through the accelerator
  -- coherency port), AXI4 to AXI3, mapped as S_AXI_GP.  user maps to
  -- AxUSER, zero-extended (bit 0 requests a coherent access).
  constant s_axi_acp_config_c : nsl_amba.axi4_mm.config_t
    := nsl_amba.axi4_mm.config(address_width => 32, data_bus_width => 64,
                               user_width => 5, id_width => 3, max_length => 16,
                               size => true, burst => true,
                               cache => true, lock => true, qos => true);

  constant ps7_s_axi_acp_write_acceptance_c : positive := 8;

  -- An M_AXI_GP port without slave: never accepts anything.
  constant m_axi_gp_slave_idle_c : nsl_amba.axi4_mm.slave_t := (
    aw => nsl_amba.axi4_mm.handshake_defaults(m_axi_gp_config_c),
    w => nsl_amba.axi4_mm.handshake_defaults(m_axi_gp_config_c),
    b => nsl_amba.axi4_mm.write_response_defaults(m_axi_gp_config_c),
    ar => nsl_amba.axi4_mm.handshake_defaults(m_axi_gp_config_c),
    r => nsl_amba.axi4_mm.read_data_defaults(m_axi_gp_config_c)
    );

  -- An S_AXI_GP port without master: never issues anything.
  constant s_axi_gp_master_idle_c : nsl_amba.axi4_mm.master_t := (
    aw => nsl_amba.axi4_mm.address_defaults(s_axi_gp_config_c),
    w => nsl_amba.axi4_mm.write_data_defaults(s_axi_gp_config_c),
    b => nsl_amba.axi4_mm.handshake_defaults(s_axi_gp_config_c),
    ar => nsl_amba.axi4_mm.address_defaults(s_axi_gp_config_c),
    r => nsl_amba.axi4_mm.handshake_defaults(s_axi_gp_config_c)
    );

  -- An S_AXI_HP port without master: never issues anything.
  constant s_axi_hp_master_idle_c : nsl_amba.axi4_mm.master_t := (
    aw => nsl_amba.axi4_mm.address_defaults(s_axi_hp_config_c),
    w => nsl_amba.axi4_mm.write_data_defaults(s_axi_hp_config_c),
    b => nsl_amba.axi4_mm.handshake_defaults(s_axi_hp_config_c),
    ar => nsl_amba.axi4_mm.address_defaults(s_axi_hp_config_c),
    r => nsl_amba.axi4_mm.handshake_defaults(s_axi_hp_config_c)
    );

  -- An S_AXI_ACP port without master: never issues anything.
  constant s_axi_acp_master_idle_c : nsl_amba.axi4_mm.master_t := (
    aw => nsl_amba.axi4_mm.address_defaults(s_axi_acp_config_c),
    w => nsl_amba.axi4_mm.write_data_defaults(s_axi_acp_config_c),
    b => nsl_amba.axi4_mm.handshake_defaults(s_axi_acp_config_c),
    ar => nsl_amba.axi4_mm.address_defaults(s_axi_acp_config_c),
    r => nsl_amba.axi4_mm.handshake_defaults(s_axi_acp_config_c)
    );

  -- Frequency of each FCLK, in Hz, 0 for an unused one.
  type ps7_fclk_frequency_vector is array (0 to 3) of natural;

  -- AFI FIFO levels of an S_AXI_HP port
  type ps7_hp_level_t is
  record
    -- RCOUNT, read data
    read_data : unsigned(7 downto 0);
    -- WCOUNT, write data
    write_data : unsigned(7 downto 0);
    -- RACOUNT, read commands
    read_command : unsigned(2 downto 0);
    -- WACOUNT, write commands
    write_command : unsigned(5 downto 0);
  end record;

  -- Precision time protocol event strobes of a GEM, one cycle pulses
  -- in the GMII clock domain of their direction.
  type ps7_gem_ptp_strobes_t is
  record
    -- Start of frame
    sof : std_ulogic;
    sync : std_ulogic;
    delay_req : std_ulogic;
    pdelay_req : std_ulogic;
    pdelay_resp : std_ulogic;
  end record;

  -- Plain instantiation of the PS7 primitive, without Vivado block
  -- design.  Only available for Zynq-7000 parts (target_part xc7z*),
  -- there is no simulation model.
  --
  -- MIO, DDR, PS_CLK, PS_PORB and PS_SRSTB are left unconnected: they
  -- are dedicated pins of the PS that need no PL routing.
  --
  -- The PL side of the PS is only functional once software configured
  -- it: clocks (FCLK dividers and enables), PS-PL level shifters
  -- (SLCR.LVL_SHFTR_EN), PL resets (SLCR.FPGA_RST_CTRL) and, for
  -- S_AXI_GP, the relevant address map.  The attributes of the
  -- primitive (clock frequencies, enabled ports) are not used for
  -- configuration by the silicon.
  --
  -- fclk_o/fclk_reset_n_o: FCLK_CLK0..3 and FCLK_RESET0..3_N.  No
  -- global buffer is inserted, fclk_o is the primitive output.
  -- fclk_frequency_c is the frequency software is expected to set for
  -- each of them.  The wrapper does not use it, it is reported for
  -- derivation of software settings and constraints.
  --
  -- With report_registers_c, elaboration reports the SLCR and AFI
  -- register fields the configuration implies, one note per field:
  --
  --   nsl_xilinx.ps7: write 0x<address> mask 0x<mask> value 0x<value> # <comment>
  --   nsl_xilinx.ps7: fclk <n> frequency <hz> Hz
  --
  -- Fields depending on how EMIO ports are used are not reported:
  -- usage is invisible from the wrapper.
  --
  -- *_config_c: configuration of each AXI port records, defaulting to
  -- the native one.  Elaboration fails unless conversion from/to
  -- native is trivial:
  -- * data width is the native one, or 32 for S_AXI_HP;
  -- * address width is 32 or less.  It is zero-extended towards the
  --   PS, M_AXI ports drop the PS address MSBs;
  -- * on M_AXI ports, ID width and max_length may be larger than
  --   native (IDs are zero-extended), size and burst are mandatory;
  -- * on S_AXI ports, ID width and max_length may be smaller than
  --   native (IDs are zero-extended);
  -- * on S_AXI_ACP, user width may be smaller than native;
  -- * cache, qos and lock may be absent.  Absent lock on M_AXI makes
  --   exclusive accesses get OKAY, software sees them fail.
  --
  -- *_clock_i: clock of the matching AXI port, the port's records are
  -- synchronous to it.  *_reset_n_o is the port's ARESETN output from
  -- the PS, synchronous to the port clock.
  --
  -- s_axi_hpN_level_o: AFI FIFO levels of the port, in its clock
  -- domain.  s_axi_hpN_read/write_issue_cap1_i select the alternate
  -- issuing capability software set for the port (AFI ISSUINGCAP
  -- registers).
  --
  -- dmac_*: DMA controller (DMA-330) peripheral request interfaces 0
  -- to 3 (the PL ones), in dmac_clock_i(n) domain, with the DMA-330
  -- semantics (see nsl_amba.dma_request.peripheral_t).
  -- dmac_reset_n_o(n) is the matching DMAn_RSTN output.
  --
  -- dmac_irq_o(n) is DMA controller event interrupt n (IRQP2F(20+n)),
  -- dmac_irq_abort_o is the DMA controller abort interrupt
  -- (IRQP2F(28)).
  --
  -- irq_f2p_i(n) is IRQF2P(n), PL to PS shared peripheral interrupt
  -- (GIC IDs 61 to 68 for 0 to 7, 84 to 91 for 8 to 15).
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
  -- controller is expected in decoded chip select mode (PERI_SEL) and
  -- the 3 SS outputs carry the binary index of the selected slave (up
  -- to 7 slaves, "111" selects none).  Decoding is combinatorial, it
  -- may glitch other slaves' cs_n during transitions.
  --
  -- gemN_*: GEM N.  gemN_tx_clock_i is the GMII TX clock the GEM runs
  -- its transmitter from, it is always routed from the PL, regardless
  -- of GMII routing.  gemN_gmii_tx_o and gemN_ptp_tx_o are synchronous
  -- to it.  gemN_gmii_rx_i, col, crs and gemN_ptp_rx_o are
  -- synchronous to gemN_gmii_rx_clock_i.  gemN_smi_* is the MDIO
  -- master.  gemN_ext_int_i is the GEM external interrupt input.
  --
  -- uartN_o/uartN_i: UART N, as a DTE.  uartN_o.dcd and .ri are always
  -- deasserted.  Inputs default to a DCE that is always ready.
  --
  -- i2cN_o/i2cN_i: I2C controller N.
  --
  -- gpio_o/gpio_i: EMIO GPIO bank, gpio_o(n)/gpio_i(n) are software
  -- GPIO 54+n.  gpio_i is read by software regardless of gpio_o(n).en.
  component ps7_wrapper is
    generic(
      m_axi_gp0_config_c : nsl_amba.axi4_mm.config_t := m_axi_gp_config_c;
      m_axi_gp1_config_c : nsl_amba.axi4_mm.config_t := m_axi_gp_config_c;
      s_axi_gp0_config_c : nsl_amba.axi4_mm.config_t := s_axi_gp_config_c;
      s_axi_gp1_config_c : nsl_amba.axi4_mm.config_t := s_axi_gp_config_c;
      s_axi_hp0_config_c : nsl_amba.axi4_mm.config_t := s_axi_hp_config_c;
      s_axi_hp1_config_c : nsl_amba.axi4_mm.config_t := s_axi_hp_config_c;
      s_axi_hp2_config_c : nsl_amba.axi4_mm.config_t := s_axi_hp_config_c;
      s_axi_hp3_config_c : nsl_amba.axi4_mm.config_t := s_axi_hp_config_c;
      s_axi_acp_config_c : nsl_amba.axi4_mm.config_t := ps7.s_axi_acp_config_c;

      spi0_decoded_cs_c : boolean := false;
      spi0_slave_count_c : natural range 0 to 7 := 0;
      spi1_decoded_cs_c : boolean := false;
      spi1_slave_count_c : natural range 0 to 7 := 0;

      fclk_frequency_c : ps7_fclk_frequency_vector := (others => 0);
      report_registers_c : boolean := true
      );
    port(
      fclk_o : out std_ulogic_vector(0 to 3);
      fclk_reset_n_o : out std_ulogic_vector(0 to 3);

      m_axi_gp0_clock_i : in std_ulogic := '0';
      m_axi_gp0_reset_n_o : out std_ulogic;
      m_axi_gp0_o : out nsl_amba.axi4_mm.master_t;
      m_axi_gp0_i : in nsl_amba.axi4_mm.slave_t := m_axi_gp_slave_idle_c;

      m_axi_gp1_clock_i : in std_ulogic := '0';
      m_axi_gp1_reset_n_o : out std_ulogic;
      m_axi_gp1_o : out nsl_amba.axi4_mm.master_t;
      m_axi_gp1_i : in nsl_amba.axi4_mm.slave_t := m_axi_gp_slave_idle_c;

      s_axi_gp0_clock_i : in std_ulogic := '0';
      s_axi_gp0_reset_n_o : out std_ulogic;
      s_axi_gp0_i : in nsl_amba.axi4_mm.master_t := s_axi_gp_master_idle_c;
      s_axi_gp0_o : out nsl_amba.axi4_mm.slave_t;

      s_axi_gp1_clock_i : in std_ulogic := '0';
      s_axi_gp1_reset_n_o : out std_ulogic;
      s_axi_gp1_i : in nsl_amba.axi4_mm.master_t := s_axi_gp_master_idle_c;
      s_axi_gp1_o : out nsl_amba.axi4_mm.slave_t;

      s_axi_hp0_clock_i : in std_ulogic := '0';
      s_axi_hp0_reset_n_o : out std_ulogic;
      s_axi_hp0_i : in nsl_amba.axi4_mm.master_t := s_axi_hp_master_idle_c;
      s_axi_hp0_o : out nsl_amba.axi4_mm.slave_t;
      s_axi_hp0_level_o : out ps7_hp_level_t;
      s_axi_hp0_read_issue_cap1_i : in std_ulogic := '0';
      s_axi_hp0_write_issue_cap1_i : in std_ulogic := '0';

      s_axi_hp1_clock_i : in std_ulogic := '0';
      s_axi_hp1_reset_n_o : out std_ulogic;
      s_axi_hp1_i : in nsl_amba.axi4_mm.master_t := s_axi_hp_master_idle_c;
      s_axi_hp1_o : out nsl_amba.axi4_mm.slave_t;
      s_axi_hp1_level_o : out ps7_hp_level_t;
      s_axi_hp1_read_issue_cap1_i : in std_ulogic := '0';
      s_axi_hp1_write_issue_cap1_i : in std_ulogic := '0';

      s_axi_hp2_clock_i : in std_ulogic := '0';
      s_axi_hp2_reset_n_o : out std_ulogic;
      s_axi_hp2_i : in nsl_amba.axi4_mm.master_t := s_axi_hp_master_idle_c;
      s_axi_hp2_o : out nsl_amba.axi4_mm.slave_t;
      s_axi_hp2_level_o : out ps7_hp_level_t;
      s_axi_hp2_read_issue_cap1_i : in std_ulogic := '0';
      s_axi_hp2_write_issue_cap1_i : in std_ulogic := '0';

      s_axi_hp3_clock_i : in std_ulogic := '0';
      s_axi_hp3_reset_n_o : out std_ulogic;
      s_axi_hp3_i : in nsl_amba.axi4_mm.master_t := s_axi_hp_master_idle_c;
      s_axi_hp3_o : out nsl_amba.axi4_mm.slave_t;
      s_axi_hp3_level_o : out ps7_hp_level_t;
      s_axi_hp3_read_issue_cap1_i : in std_ulogic := '0';
      s_axi_hp3_write_issue_cap1_i : in std_ulogic := '0';

      s_axi_acp_clock_i : in std_ulogic := '0';
      s_axi_acp_reset_n_o : out std_ulogic;
      s_axi_acp_i : in nsl_amba.axi4_mm.master_t := s_axi_acp_master_idle_c;
      s_axi_acp_o : out nsl_amba.axi4_mm.slave_t;

      dmac_clock_i : in std_ulogic_vector(0 to 3) := (others => '0');
      dmac_reset_n_o : out std_ulogic_vector(0 to 3);
      dmac_periph_i : in nsl_amba.dma_request.peripheral_vector(0 to 3)
        := (others => nsl_amba.dma_request.peripheral_idle_c);
      dmac_periph_o : out nsl_amba.dma_request.dmac_vector(0 to 3);

      dmac_irq_o : out std_ulogic_vector(0 to 7);
      dmac_irq_abort_o : out std_ulogic;
      irq_f2p_i : in std_ulogic_vector(0 to 15) := (others => '0');

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
      gem0_ptp_tx_o : out ps7_gem_ptp_strobes_t;
      gem0_ptp_rx_o : out ps7_gem_ptp_strobes_t;
      gem0_ext_int_i : in std_ulogic := '0';

      gem1_tx_clock_i : in std_ulogic := '0';
      gem1_gmii_tx_o : out nsl_mii.gmii.gmii_io_group_t;
      gem1_gmii_rx_clock_i : in std_ulogic := '0';
      gem1_gmii_rx_i : in nsl_mii.gmii.gmii_io_group_t := nsl_mii.gmii.gmii_io_group_idle_c;
      gem1_gmii_col_i : in std_ulogic := '0';
      gem1_gmii_crs_i : in std_ulogic := '0';
      gem1_smi_o : out nsl_smi.smi.smi_master_o;
      gem1_smi_i : in nsl_smi.smi.smi_master_i := nsl_smi.smi.smi_master_i_idle_c;
      gem1_ptp_tx_o : out ps7_gem_ptp_strobes_t;
      gem1_ptp_rx_o : out ps7_gem_ptp_strobes_t;
      gem1_ext_int_i : in std_ulogic := '0';

      uart0_o : out nsl_uart.uart.uart_signals_t;
      uart0_i : in nsl_uart.uart.uart_signals_t := nsl_uart.uart.uart_dce_absent_c;
      uart1_o : out nsl_uart.uart.uart_signals_t;
      uart1_i : in nsl_uart.uart.uart_signals_t := nsl_uart.uart.uart_dce_absent_c;

      i2c0_o : out nsl_i2c.i2c.i2c_o;
      i2c0_i : in nsl_i2c.i2c.i2c_i := nsl_i2c.i2c.i2c_i_idle_c;
      i2c1_o : out nsl_i2c.i2c.i2c_o;
      i2c1_i : in nsl_i2c.i2c.i2c_i := nsl_i2c.i2c.i2c_i_idle_c;

      gpio_o : out nsl_io.io.tristated_vector(0 to 63);
      gpio_i : in std_ulogic_vector(0 to 63) := (others => '0')
      );
  end component;

  -- Write ID generator for an AXI3 slave port fed by an AXI4 master,
  -- used by ps7_wrapper on S_AXI_GP ports.
  --
  -- Queues the ID of every AW handshake (up to depth_c of them) and
  -- presents the oldest one on w_id_o.  Pops it on the handshake of
  -- the last W beat of a burst.  With the queue empty, w_id_o is
  -- aw_id_i: a burst may run, and even complete, before its AW
  -- handshake.  At most one burst may complete ahead of its AW: the
  -- next burst is held until that AW handshake, as aw_id_i does not
  -- show its ID until then.
  --
  -- *_i without other qualifier come from the master, aw_ready_i and
  -- w_ready_i from the slave.  aw_valid_o/w_valid_o go to the slave,
  -- aw_ready_o/w_ready_o to the master: they are their input
  -- counterpart gated, combinationally, by queue not full (AW) and
  -- by the availability of an ID (W), which never depends on
  -- aw_ready_i.
  component ps7_axi3_wid_tracker is
    generic(
      id_width_c : positive;
      depth_c : positive := ps7_s_axi_gp_write_acceptance_c
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      aw_valid_i : in std_ulogic;
      aw_id_i : in std_ulogic_vector(id_width_c-1 downto 0);
      aw_valid_o : out std_ulogic;
      aw_ready_i : in std_ulogic;
      aw_ready_o : out std_ulogic;

      w_valid_i : in std_ulogic;
      w_last_i : in std_ulogic;
      w_valid_o : out std_ulogic;
      w_ready_i : in std_ulogic;
      w_ready_o : out std_ulogic;
      w_id_o : out std_ulogic_vector(id_width_c-1 downto 0)
      );
  end component;

end package;
