library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_xilinx, nsl_data, nsl_spi, nsl_mii, nsl_smi, nsl_uart, nsl_i2c, nsl_io;
use nsl_amba.axi4_mm.all;
use nsl_xilinx.ps7.all;
use nsl_data.endian.all;

entity ps7_wrapper is
  generic(
    m_axi_gp0_config_c : nsl_amba.axi4_mm.config_t := m_axi_gp_config_c;
    m_axi_gp1_config_c : nsl_amba.axi4_mm.config_t := m_axi_gp_config_c;
    s_axi_gp0_config_c : nsl_amba.axi4_mm.config_t := s_axi_gp_config_c;
    s_axi_gp1_config_c : nsl_amba.axi4_mm.config_t := s_axi_gp_config_c;
    s_axi_hp0_config_c : nsl_amba.axi4_mm.config_t := s_axi_hp_config_c;
    s_axi_hp1_config_c : nsl_amba.axi4_mm.config_t := s_axi_hp_config_c;
    s_axi_hp2_config_c : nsl_amba.axi4_mm.config_t := s_axi_hp_config_c;
    s_axi_hp3_config_c : nsl_amba.axi4_mm.config_t := s_axi_hp_config_c;
    s_axi_acp_config_c : nsl_amba.axi4_mm.config_t := nsl_xilinx.ps7.s_axi_acp_config_c;

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
end entity;

-- The PS7 primitive has no simulation model, this architecture is only
-- meant for synthesis.  Every input of the primitive this wrapper does
-- not expose is tied to its inactive value (as Xilinx processing_system7
-- IP does for disabled interfaces), every output it does not expose is
-- left open.  SPI slave select inputs are tied high: SPI controllers
-- are only usable as masters, this prevents mode faults.  Dedicated PS pins (MIO, DDR, PS_CLK,
-- PS_PORB, PS_SRSTB) are left unconnected.
architecture zynq7 of ps7_wrapper is

  attribute BOX_TYPE : string;

  component PS7
    port(
      DMA0DATYPE : out std_logic_vector(1 downto 0);
      DMA0DAVALID : out std_ulogic;
      DMA0DRREADY : out std_ulogic;
      DMA0RSTN : out std_ulogic;
      DMA1DATYPE : out std_logic_vector(1 downto 0);
      DMA1DAVALID : out std_ulogic;
      DMA1DRREADY : out std_ulogic;
      DMA1RSTN : out std_ulogic;
      DMA2DATYPE : out std_logic_vector(1 downto 0);
      DMA2DAVALID : out std_ulogic;
      DMA2DRREADY : out std_ulogic;
      DMA2RSTN : out std_ulogic;
      DMA3DATYPE : out std_logic_vector(1 downto 0);
      DMA3DAVALID : out std_ulogic;
      DMA3DRREADY : out std_ulogic;
      DMA3RSTN : out std_ulogic;
      EMIOCAN0PHYTX : out std_ulogic;
      EMIOCAN1PHYTX : out std_ulogic;
      EMIOENET0GMIITXD : out std_logic_vector(7 downto 0);
      EMIOENET0GMIITXEN : out std_ulogic;
      EMIOENET0GMIITXER : out std_ulogic;
      EMIOENET0MDIOMDC : out std_ulogic;
      EMIOENET0MDIOO : out std_ulogic;
      EMIOENET0MDIOTN : out std_ulogic;
      EMIOENET0PTPDELAYREQRX : out std_ulogic;
      EMIOENET0PTPDELAYREQTX : out std_ulogic;
      EMIOENET0PTPPDELAYREQRX : out std_ulogic;
      EMIOENET0PTPPDELAYREQTX : out std_ulogic;
      EMIOENET0PTPPDELAYRESPRX : out std_ulogic;
      EMIOENET0PTPPDELAYRESPTX : out std_ulogic;
      EMIOENET0PTPSYNCFRAMERX : out std_ulogic;
      EMIOENET0PTPSYNCFRAMETX : out std_ulogic;
      EMIOENET0SOFRX : out std_ulogic;
      EMIOENET0SOFTX : out std_ulogic;
      EMIOENET1GMIITXD : out std_logic_vector(7 downto 0);
      EMIOENET1GMIITXEN : out std_ulogic;
      EMIOENET1GMIITXER : out std_ulogic;
      EMIOENET1MDIOMDC : out std_ulogic;
      EMIOENET1MDIOO : out std_ulogic;
      EMIOENET1MDIOTN : out std_ulogic;
      EMIOENET1PTPDELAYREQRX : out std_ulogic;
      EMIOENET1PTPDELAYREQTX : out std_ulogic;
      EMIOENET1PTPPDELAYREQRX : out std_ulogic;
      EMIOENET1PTPPDELAYREQTX : out std_ulogic;
      EMIOENET1PTPPDELAYRESPRX : out std_ulogic;
      EMIOENET1PTPPDELAYRESPTX : out std_ulogic;
      EMIOENET1PTPSYNCFRAMERX : out std_ulogic;
      EMIOENET1PTPSYNCFRAMETX : out std_ulogic;
      EMIOENET1SOFRX : out std_ulogic;
      EMIOENET1SOFTX : out std_ulogic;
      EMIOGPIOO : out std_logic_vector(63 downto 0);
      EMIOGPIOTN : out std_logic_vector(63 downto 0);
      EMIOI2C0SCLO : out std_ulogic;
      EMIOI2C0SCLTN : out std_ulogic;
      EMIOI2C0SDAO : out std_ulogic;
      EMIOI2C0SDATN : out std_ulogic;
      EMIOI2C1SCLO : out std_ulogic;
      EMIOI2C1SCLTN : out std_ulogic;
      EMIOI2C1SDAO : out std_ulogic;
      EMIOI2C1SDATN : out std_ulogic;
      EMIOPJTAGTDO : out std_ulogic;
      EMIOPJTAGTDTN : out std_ulogic;
      EMIOSDIO0BUSPOW : out std_ulogic;
      EMIOSDIO0BUSVOLT : out std_logic_vector(2 downto 0);
      EMIOSDIO0CLK : out std_ulogic;
      EMIOSDIO0CMDO : out std_ulogic;
      EMIOSDIO0CMDTN : out std_ulogic;
      EMIOSDIO0DATAO : out std_logic_vector(3 downto 0);
      EMIOSDIO0DATATN : out std_logic_vector(3 downto 0);
      EMIOSDIO0LED : out std_ulogic;
      EMIOSDIO1BUSPOW : out std_ulogic;
      EMIOSDIO1BUSVOLT : out std_logic_vector(2 downto 0);
      EMIOSDIO1CLK : out std_ulogic;
      EMIOSDIO1CMDO : out std_ulogic;
      EMIOSDIO1CMDTN : out std_ulogic;
      EMIOSDIO1DATAO : out std_logic_vector(3 downto 0);
      EMIOSDIO1DATATN : out std_logic_vector(3 downto 0);
      EMIOSDIO1LED : out std_ulogic;
      EMIOSPI0MO : out std_ulogic;
      EMIOSPI0MOTN : out std_ulogic;
      EMIOSPI0SCLKO : out std_ulogic;
      EMIOSPI0SCLKTN : out std_ulogic;
      EMIOSPI0SO : out std_ulogic;
      EMIOSPI0SSNTN : out std_ulogic;
      EMIOSPI0SSON : out std_logic_vector(2 downto 0);
      EMIOSPI0STN : out std_ulogic;
      EMIOSPI1MO : out std_ulogic;
      EMIOSPI1MOTN : out std_ulogic;
      EMIOSPI1SCLKO : out std_ulogic;
      EMIOSPI1SCLKTN : out std_ulogic;
      EMIOSPI1SO : out std_ulogic;
      EMIOSPI1SSNTN : out std_ulogic;
      EMIOSPI1SSON : out std_logic_vector(2 downto 0);
      EMIOSPI1STN : out std_ulogic;
      EMIOTRACECTL : out std_ulogic;
      EMIOTRACEDATA : out std_logic_vector(31 downto 0);
      EMIOTTC0WAVEO : out std_logic_vector(2 downto 0);
      EMIOTTC1WAVEO : out std_logic_vector(2 downto 0);
      EMIOUART0DTRN : out std_ulogic;
      EMIOUART0RTSN : out std_ulogic;
      EMIOUART0TX : out std_ulogic;
      EMIOUART1DTRN : out std_ulogic;
      EMIOUART1RTSN : out std_ulogic;
      EMIOUART1TX : out std_ulogic;
      EMIOUSB0PORTINDCTL : out std_logic_vector(1 downto 0);
      EMIOUSB0VBUSPWRSELECT : out std_ulogic;
      EMIOUSB1PORTINDCTL : out std_logic_vector(1 downto 0);
      EMIOUSB1VBUSPWRSELECT : out std_ulogic;
      EMIOWDTRSTO : out std_ulogic;
      EVENTEVENTO : out std_ulogic;
      EVENTSTANDBYWFE : out std_logic_vector(1 downto 0);
      EVENTSTANDBYWFI : out std_logic_vector(1 downto 0);
      FCLKCLK : out std_logic_vector(3 downto 0);
      FCLKRESETN : out std_logic_vector(3 downto 0);
      FTMTF2PTRIGACK : out std_logic_vector(3 downto 0);
      FTMTP2FDEBUG : out std_logic_vector(31 downto 0);
      FTMTP2FTRIG : out std_logic_vector(3 downto 0);
      IRQP2F : out std_logic_vector(28 downto 0);
      MAXIGP0ARADDR : out std_logic_vector(31 downto 0);
      MAXIGP0ARBURST : out std_logic_vector(1 downto 0);
      MAXIGP0ARCACHE : out std_logic_vector(3 downto 0);
      MAXIGP0ARESETN : out std_ulogic;
      MAXIGP0ARID : out std_logic_vector(11 downto 0);
      MAXIGP0ARLEN : out std_logic_vector(3 downto 0);
      MAXIGP0ARLOCK : out std_logic_vector(1 downto 0);
      MAXIGP0ARPROT : out std_logic_vector(2 downto 0);
      MAXIGP0ARQOS : out std_logic_vector(3 downto 0);
      MAXIGP0ARSIZE : out std_logic_vector(1 downto 0);
      MAXIGP0ARVALID : out std_ulogic;
      MAXIGP0AWADDR : out std_logic_vector(31 downto 0);
      MAXIGP0AWBURST : out std_logic_vector(1 downto 0);
      MAXIGP0AWCACHE : out std_logic_vector(3 downto 0);
      MAXIGP0AWID : out std_logic_vector(11 downto 0);
      MAXIGP0AWLEN : out std_logic_vector(3 downto 0);
      MAXIGP0AWLOCK : out std_logic_vector(1 downto 0);
      MAXIGP0AWPROT : out std_logic_vector(2 downto 0);
      MAXIGP0AWQOS : out std_logic_vector(3 downto 0);
      MAXIGP0AWSIZE : out std_logic_vector(1 downto 0);
      MAXIGP0AWVALID : out std_ulogic;
      MAXIGP0BREADY : out std_ulogic;
      MAXIGP0RREADY : out std_ulogic;
      MAXIGP0WDATA : out std_logic_vector(31 downto 0);
      MAXIGP0WID : out std_logic_vector(11 downto 0);
      MAXIGP0WLAST : out std_ulogic;
      MAXIGP0WSTRB : out std_logic_vector(3 downto 0);
      MAXIGP0WVALID : out std_ulogic;
      MAXIGP1ARADDR : out std_logic_vector(31 downto 0);
      MAXIGP1ARBURST : out std_logic_vector(1 downto 0);
      MAXIGP1ARCACHE : out std_logic_vector(3 downto 0);
      MAXIGP1ARESETN : out std_ulogic;
      MAXIGP1ARID : out std_logic_vector(11 downto 0);
      MAXIGP1ARLEN : out std_logic_vector(3 downto 0);
      MAXIGP1ARLOCK : out std_logic_vector(1 downto 0);
      MAXIGP1ARPROT : out std_logic_vector(2 downto 0);
      MAXIGP1ARQOS : out std_logic_vector(3 downto 0);
      MAXIGP1ARSIZE : out std_logic_vector(1 downto 0);
      MAXIGP1ARVALID : out std_ulogic;
      MAXIGP1AWADDR : out std_logic_vector(31 downto 0);
      MAXIGP1AWBURST : out std_logic_vector(1 downto 0);
      MAXIGP1AWCACHE : out std_logic_vector(3 downto 0);
      MAXIGP1AWID : out std_logic_vector(11 downto 0);
      MAXIGP1AWLEN : out std_logic_vector(3 downto 0);
      MAXIGP1AWLOCK : out std_logic_vector(1 downto 0);
      MAXIGP1AWPROT : out std_logic_vector(2 downto 0);
      MAXIGP1AWQOS : out std_logic_vector(3 downto 0);
      MAXIGP1AWSIZE : out std_logic_vector(1 downto 0);
      MAXIGP1AWVALID : out std_ulogic;
      MAXIGP1BREADY : out std_ulogic;
      MAXIGP1RREADY : out std_ulogic;
      MAXIGP1WDATA : out std_logic_vector(31 downto 0);
      MAXIGP1WID : out std_logic_vector(11 downto 0);
      MAXIGP1WLAST : out std_ulogic;
      MAXIGP1WSTRB : out std_logic_vector(3 downto 0);
      MAXIGP1WVALID : out std_ulogic;
      SAXIACPARESETN : out std_ulogic;
      SAXIACPARREADY : out std_ulogic;
      SAXIACPAWREADY : out std_ulogic;
      SAXIACPBID : out std_logic_vector(2 downto 0);
      SAXIACPBRESP : out std_logic_vector(1 downto 0);
      SAXIACPBVALID : out std_ulogic;
      SAXIACPRDATA : out std_logic_vector(63 downto 0);
      SAXIACPRID : out std_logic_vector(2 downto 0);
      SAXIACPRLAST : out std_ulogic;
      SAXIACPRRESP : out std_logic_vector(1 downto 0);
      SAXIACPRVALID : out std_ulogic;
      SAXIACPWREADY : out std_ulogic;
      SAXIGP0ARESETN : out std_ulogic;
      SAXIGP0ARREADY : out std_ulogic;
      SAXIGP0AWREADY : out std_ulogic;
      SAXIGP0BID : out std_logic_vector(5 downto 0);
      SAXIGP0BRESP : out std_logic_vector(1 downto 0);
      SAXIGP0BVALID : out std_ulogic;
      SAXIGP0RDATA : out std_logic_vector(31 downto 0);
      SAXIGP0RID : out std_logic_vector(5 downto 0);
      SAXIGP0RLAST : out std_ulogic;
      SAXIGP0RRESP : out std_logic_vector(1 downto 0);
      SAXIGP0RVALID : out std_ulogic;
      SAXIGP0WREADY : out std_ulogic;
      SAXIGP1ARESETN : out std_ulogic;
      SAXIGP1ARREADY : out std_ulogic;
      SAXIGP1AWREADY : out std_ulogic;
      SAXIGP1BID : out std_logic_vector(5 downto 0);
      SAXIGP1BRESP : out std_logic_vector(1 downto 0);
      SAXIGP1BVALID : out std_ulogic;
      SAXIGP1RDATA : out std_logic_vector(31 downto 0);
      SAXIGP1RID : out std_logic_vector(5 downto 0);
      SAXIGP1RLAST : out std_ulogic;
      SAXIGP1RRESP : out std_logic_vector(1 downto 0);
      SAXIGP1RVALID : out std_ulogic;
      SAXIGP1WREADY : out std_ulogic;
      SAXIHP0ARESETN : out std_ulogic;
      SAXIHP0ARREADY : out std_ulogic;
      SAXIHP0AWREADY : out std_ulogic;
      SAXIHP0BID : out std_logic_vector(5 downto 0);
      SAXIHP0BRESP : out std_logic_vector(1 downto 0);
      SAXIHP0BVALID : out std_ulogic;
      SAXIHP0RACOUNT : out std_logic_vector(2 downto 0);
      SAXIHP0RCOUNT : out std_logic_vector(7 downto 0);
      SAXIHP0RDATA : out std_logic_vector(63 downto 0);
      SAXIHP0RID : out std_logic_vector(5 downto 0);
      SAXIHP0RLAST : out std_ulogic;
      SAXIHP0RRESP : out std_logic_vector(1 downto 0);
      SAXIHP0RVALID : out std_ulogic;
      SAXIHP0WACOUNT : out std_logic_vector(5 downto 0);
      SAXIHP0WCOUNT : out std_logic_vector(7 downto 0);
      SAXIHP0WREADY : out std_ulogic;
      SAXIHP1ARESETN : out std_ulogic;
      SAXIHP1ARREADY : out std_ulogic;
      SAXIHP1AWREADY : out std_ulogic;
      SAXIHP1BID : out std_logic_vector(5 downto 0);
      SAXIHP1BRESP : out std_logic_vector(1 downto 0);
      SAXIHP1BVALID : out std_ulogic;
      SAXIHP1RACOUNT : out std_logic_vector(2 downto 0);
      SAXIHP1RCOUNT : out std_logic_vector(7 downto 0);
      SAXIHP1RDATA : out std_logic_vector(63 downto 0);
      SAXIHP1RID : out std_logic_vector(5 downto 0);
      SAXIHP1RLAST : out std_ulogic;
      SAXIHP1RRESP : out std_logic_vector(1 downto 0);
      SAXIHP1RVALID : out std_ulogic;
      SAXIHP1WACOUNT : out std_logic_vector(5 downto 0);
      SAXIHP1WCOUNT : out std_logic_vector(7 downto 0);
      SAXIHP1WREADY : out std_ulogic;
      SAXIHP2ARESETN : out std_ulogic;
      SAXIHP2ARREADY : out std_ulogic;
      SAXIHP2AWREADY : out std_ulogic;
      SAXIHP2BID : out std_logic_vector(5 downto 0);
      SAXIHP2BRESP : out std_logic_vector(1 downto 0);
      SAXIHP2BVALID : out std_ulogic;
      SAXIHP2RACOUNT : out std_logic_vector(2 downto 0);
      SAXIHP2RCOUNT : out std_logic_vector(7 downto 0);
      SAXIHP2RDATA : out std_logic_vector(63 downto 0);
      SAXIHP2RID : out std_logic_vector(5 downto 0);
      SAXIHP2RLAST : out std_ulogic;
      SAXIHP2RRESP : out std_logic_vector(1 downto 0);
      SAXIHP2RVALID : out std_ulogic;
      SAXIHP2WACOUNT : out std_logic_vector(5 downto 0);
      SAXIHP2WCOUNT : out std_logic_vector(7 downto 0);
      SAXIHP2WREADY : out std_ulogic;
      SAXIHP3ARESETN : out std_ulogic;
      SAXIHP3ARREADY : out std_ulogic;
      SAXIHP3AWREADY : out std_ulogic;
      SAXIHP3BID : out std_logic_vector(5 downto 0);
      SAXIHP3BRESP : out std_logic_vector(1 downto 0);
      SAXIHP3BVALID : out std_ulogic;
      SAXIHP3RACOUNT : out std_logic_vector(2 downto 0);
      SAXIHP3RCOUNT : out std_logic_vector(7 downto 0);
      SAXIHP3RDATA : out std_logic_vector(63 downto 0);
      SAXIHP3RID : out std_logic_vector(5 downto 0);
      SAXIHP3RLAST : out std_ulogic;
      SAXIHP3RRESP : out std_logic_vector(1 downto 0);
      SAXIHP3RVALID : out std_ulogic;
      SAXIHP3WACOUNT : out std_logic_vector(5 downto 0);
      SAXIHP3WCOUNT : out std_logic_vector(7 downto 0);
      SAXIHP3WREADY : out std_ulogic;
      DDRA : inout std_logic_vector(14 downto 0);
      DDRBA : inout std_logic_vector(2 downto 0);
      DDRCASB : inout std_ulogic;
      DDRCKE : inout std_ulogic;
      DDRCKN : inout std_ulogic;
      DDRCKP : inout std_ulogic;
      DDRCSB : inout std_ulogic;
      DDRDM : inout std_logic_vector(3 downto 0);
      DDRDQ : inout std_logic_vector(31 downto 0);
      DDRDQSN : inout std_logic_vector(3 downto 0);
      DDRDQSP : inout std_logic_vector(3 downto 0);
      DDRDRSTB : inout std_ulogic;
      DDRODT : inout std_ulogic;
      DDRRASB : inout std_ulogic;
      DDRVRN : inout std_ulogic;
      DDRVRP : inout std_ulogic;
      DDRWEB : inout std_ulogic;
      MIO : inout std_logic_vector(53 downto 0);
      PSCLK : inout std_ulogic;
      PSPORB : inout std_ulogic;
      PSSRSTB : inout std_ulogic;
      DDRARB : in std_logic_vector(3 downto 0);
      DMA0ACLK : in std_ulogic;
      DMA0DAREADY : in std_ulogic;
      DMA0DRLAST : in std_ulogic;
      DMA0DRTYPE : in std_logic_vector(1 downto 0);
      DMA0DRVALID : in std_ulogic;
      DMA1ACLK : in std_ulogic;
      DMA1DAREADY : in std_ulogic;
      DMA1DRLAST : in std_ulogic;
      DMA1DRTYPE : in std_logic_vector(1 downto 0);
      DMA1DRVALID : in std_ulogic;
      DMA2ACLK : in std_ulogic;
      DMA2DAREADY : in std_ulogic;
      DMA2DRLAST : in std_ulogic;
      DMA2DRTYPE : in std_logic_vector(1 downto 0);
      DMA2DRVALID : in std_ulogic;
      DMA3ACLK : in std_ulogic;
      DMA3DAREADY : in std_ulogic;
      DMA3DRLAST : in std_ulogic;
      DMA3DRTYPE : in std_logic_vector(1 downto 0);
      DMA3DRVALID : in std_ulogic;
      EMIOCAN0PHYRX : in std_ulogic;
      EMIOCAN1PHYRX : in std_ulogic;
      EMIOENET0EXTINTIN : in std_ulogic;
      EMIOENET0GMIICOL : in std_ulogic;
      EMIOENET0GMIICRS : in std_ulogic;
      EMIOENET0GMIIRXCLK : in std_ulogic;
      EMIOENET0GMIIRXD : in std_logic_vector(7 downto 0);
      EMIOENET0GMIIRXDV : in std_ulogic;
      EMIOENET0GMIIRXER : in std_ulogic;
      EMIOENET0GMIITXCLK : in std_ulogic;
      EMIOENET0MDIOI : in std_ulogic;
      EMIOENET1EXTINTIN : in std_ulogic;
      EMIOENET1GMIICOL : in std_ulogic;
      EMIOENET1GMIICRS : in std_ulogic;
      EMIOENET1GMIIRXCLK : in std_ulogic;
      EMIOENET1GMIIRXD : in std_logic_vector(7 downto 0);
      EMIOENET1GMIIRXDV : in std_ulogic;
      EMIOENET1GMIIRXER : in std_ulogic;
      EMIOENET1GMIITXCLK : in std_ulogic;
      EMIOENET1MDIOI : in std_ulogic;
      EMIOGPIOI : in std_logic_vector(63 downto 0);
      EMIOI2C0SCLI : in std_ulogic;
      EMIOI2C0SDAI : in std_ulogic;
      EMIOI2C1SCLI : in std_ulogic;
      EMIOI2C1SDAI : in std_ulogic;
      EMIOPJTAGTCK : in std_ulogic;
      EMIOPJTAGTDI : in std_ulogic;
      EMIOPJTAGTMS : in std_ulogic;
      EMIOSDIO0CDN : in std_ulogic;
      EMIOSDIO0CLKFB : in std_ulogic;
      EMIOSDIO0CMDI : in std_ulogic;
      EMIOSDIO0DATAI : in std_logic_vector(3 downto 0);
      EMIOSDIO0WP : in std_ulogic;
      EMIOSDIO1CDN : in std_ulogic;
      EMIOSDIO1CLKFB : in std_ulogic;
      EMIOSDIO1CMDI : in std_ulogic;
      EMIOSDIO1DATAI : in std_logic_vector(3 downto 0);
      EMIOSDIO1WP : in std_ulogic;
      EMIOSPI0MI : in std_ulogic;
      EMIOSPI0SCLKI : in std_ulogic;
      EMIOSPI0SI : in std_ulogic;
      EMIOSPI0SSIN : in std_ulogic;
      EMIOSPI1MI : in std_ulogic;
      EMIOSPI1SCLKI : in std_ulogic;
      EMIOSPI1SI : in std_ulogic;
      EMIOSPI1SSIN : in std_ulogic;
      EMIOSRAMINTIN : in std_ulogic;
      EMIOTRACECLK : in std_ulogic;
      EMIOTTC0CLKI : in std_logic_vector(2 downto 0);
      EMIOTTC1CLKI : in std_logic_vector(2 downto 0);
      EMIOUART0CTSN : in std_ulogic;
      EMIOUART0DCDN : in std_ulogic;
      EMIOUART0DSRN : in std_ulogic;
      EMIOUART0RIN : in std_ulogic;
      EMIOUART0RX : in std_ulogic;
      EMIOUART1CTSN : in std_ulogic;
      EMIOUART1DCDN : in std_ulogic;
      EMIOUART1DSRN : in std_ulogic;
      EMIOUART1RIN : in std_ulogic;
      EMIOUART1RX : in std_ulogic;
      EMIOUSB0VBUSPWRFAULT : in std_ulogic;
      EMIOUSB1VBUSPWRFAULT : in std_ulogic;
      EMIOWDTCLKI : in std_ulogic;
      EVENTEVENTI : in std_ulogic;
      FCLKCLKTRIGN : in std_logic_vector(3 downto 0);
      FPGAIDLEN : in std_ulogic;
      FTMDTRACEINATID : in std_logic_vector(3 downto 0);
      FTMDTRACEINCLOCK : in std_ulogic;
      FTMDTRACEINDATA : in std_logic_vector(31 downto 0);
      FTMDTRACEINVALID : in std_ulogic;
      FTMTF2PDEBUG : in std_logic_vector(31 downto 0);
      FTMTF2PTRIG : in std_logic_vector(3 downto 0);
      FTMTP2FTRIGACK : in std_logic_vector(3 downto 0);
      IRQF2P : in std_logic_vector(19 downto 0);
      MAXIGP0ACLK : in std_ulogic;
      MAXIGP0ARREADY : in std_ulogic;
      MAXIGP0AWREADY : in std_ulogic;
      MAXIGP0BID : in std_logic_vector(11 downto 0);
      MAXIGP0BRESP : in std_logic_vector(1 downto 0);
      MAXIGP0BVALID : in std_ulogic;
      MAXIGP0RDATA : in std_logic_vector(31 downto 0);
      MAXIGP0RID : in std_logic_vector(11 downto 0);
      MAXIGP0RLAST : in std_ulogic;
      MAXIGP0RRESP : in std_logic_vector(1 downto 0);
      MAXIGP0RVALID : in std_ulogic;
      MAXIGP0WREADY : in std_ulogic;
      MAXIGP1ACLK : in std_ulogic;
      MAXIGP1ARREADY : in std_ulogic;
      MAXIGP1AWREADY : in std_ulogic;
      MAXIGP1BID : in std_logic_vector(11 downto 0);
      MAXIGP1BRESP : in std_logic_vector(1 downto 0);
      MAXIGP1BVALID : in std_ulogic;
      MAXIGP1RDATA : in std_logic_vector(31 downto 0);
      MAXIGP1RID : in std_logic_vector(11 downto 0);
      MAXIGP1RLAST : in std_ulogic;
      MAXIGP1RRESP : in std_logic_vector(1 downto 0);
      MAXIGP1RVALID : in std_ulogic;
      MAXIGP1WREADY : in std_ulogic;
      SAXIACPACLK : in std_ulogic;
      SAXIACPARADDR : in std_logic_vector(31 downto 0);
      SAXIACPARBURST : in std_logic_vector(1 downto 0);
      SAXIACPARCACHE : in std_logic_vector(3 downto 0);
      SAXIACPARID : in std_logic_vector(2 downto 0);
      SAXIACPARLEN : in std_logic_vector(3 downto 0);
      SAXIACPARLOCK : in std_logic_vector(1 downto 0);
      SAXIACPARPROT : in std_logic_vector(2 downto 0);
      SAXIACPARQOS : in std_logic_vector(3 downto 0);
      SAXIACPARSIZE : in std_logic_vector(1 downto 0);
      SAXIACPARUSER : in std_logic_vector(4 downto 0);
      SAXIACPARVALID : in std_ulogic;
      SAXIACPAWADDR : in std_logic_vector(31 downto 0);
      SAXIACPAWBURST : in std_logic_vector(1 downto 0);
      SAXIACPAWCACHE : in std_logic_vector(3 downto 0);
      SAXIACPAWID : in std_logic_vector(2 downto 0);
      SAXIACPAWLEN : in std_logic_vector(3 downto 0);
      SAXIACPAWLOCK : in std_logic_vector(1 downto 0);
      SAXIACPAWPROT : in std_logic_vector(2 downto 0);
      SAXIACPAWQOS : in std_logic_vector(3 downto 0);
      SAXIACPAWSIZE : in std_logic_vector(1 downto 0);
      SAXIACPAWUSER : in std_logic_vector(4 downto 0);
      SAXIACPAWVALID : in std_ulogic;
      SAXIACPBREADY : in std_ulogic;
      SAXIACPRREADY : in std_ulogic;
      SAXIACPWDATA : in std_logic_vector(63 downto 0);
      SAXIACPWID : in std_logic_vector(2 downto 0);
      SAXIACPWLAST : in std_ulogic;
      SAXIACPWSTRB : in std_logic_vector(7 downto 0);
      SAXIACPWVALID : in std_ulogic;
      SAXIGP0ACLK : in std_ulogic;
      SAXIGP0ARADDR : in std_logic_vector(31 downto 0);
      SAXIGP0ARBURST : in std_logic_vector(1 downto 0);
      SAXIGP0ARCACHE : in std_logic_vector(3 downto 0);
      SAXIGP0ARID : in std_logic_vector(5 downto 0);
      SAXIGP0ARLEN : in std_logic_vector(3 downto 0);
      SAXIGP0ARLOCK : in std_logic_vector(1 downto 0);
      SAXIGP0ARPROT : in std_logic_vector(2 downto 0);
      SAXIGP0ARQOS : in std_logic_vector(3 downto 0);
      SAXIGP0ARSIZE : in std_logic_vector(1 downto 0);
      SAXIGP0ARVALID : in std_ulogic;
      SAXIGP0AWADDR : in std_logic_vector(31 downto 0);
      SAXIGP0AWBURST : in std_logic_vector(1 downto 0);
      SAXIGP0AWCACHE : in std_logic_vector(3 downto 0);
      SAXIGP0AWID : in std_logic_vector(5 downto 0);
      SAXIGP0AWLEN : in std_logic_vector(3 downto 0);
      SAXIGP0AWLOCK : in std_logic_vector(1 downto 0);
      SAXIGP0AWPROT : in std_logic_vector(2 downto 0);
      SAXIGP0AWQOS : in std_logic_vector(3 downto 0);
      SAXIGP0AWSIZE : in std_logic_vector(1 downto 0);
      SAXIGP0AWVALID : in std_ulogic;
      SAXIGP0BREADY : in std_ulogic;
      SAXIGP0RREADY : in std_ulogic;
      SAXIGP0WDATA : in std_logic_vector(31 downto 0);
      SAXIGP0WID : in std_logic_vector(5 downto 0);
      SAXIGP0WLAST : in std_ulogic;
      SAXIGP0WSTRB : in std_logic_vector(3 downto 0);
      SAXIGP0WVALID : in std_ulogic;
      SAXIGP1ACLK : in std_ulogic;
      SAXIGP1ARADDR : in std_logic_vector(31 downto 0);
      SAXIGP1ARBURST : in std_logic_vector(1 downto 0);
      SAXIGP1ARCACHE : in std_logic_vector(3 downto 0);
      SAXIGP1ARID : in std_logic_vector(5 downto 0);
      SAXIGP1ARLEN : in std_logic_vector(3 downto 0);
      SAXIGP1ARLOCK : in std_logic_vector(1 downto 0);
      SAXIGP1ARPROT : in std_logic_vector(2 downto 0);
      SAXIGP1ARQOS : in std_logic_vector(3 downto 0);
      SAXIGP1ARSIZE : in std_logic_vector(1 downto 0);
      SAXIGP1ARVALID : in std_ulogic;
      SAXIGP1AWADDR : in std_logic_vector(31 downto 0);
      SAXIGP1AWBURST : in std_logic_vector(1 downto 0);
      SAXIGP1AWCACHE : in std_logic_vector(3 downto 0);
      SAXIGP1AWID : in std_logic_vector(5 downto 0);
      SAXIGP1AWLEN : in std_logic_vector(3 downto 0);
      SAXIGP1AWLOCK : in std_logic_vector(1 downto 0);
      SAXIGP1AWPROT : in std_logic_vector(2 downto 0);
      SAXIGP1AWQOS : in std_logic_vector(3 downto 0);
      SAXIGP1AWSIZE : in std_logic_vector(1 downto 0);
      SAXIGP1AWVALID : in std_ulogic;
      SAXIGP1BREADY : in std_ulogic;
      SAXIGP1RREADY : in std_ulogic;
      SAXIGP1WDATA : in std_logic_vector(31 downto 0);
      SAXIGP1WID : in std_logic_vector(5 downto 0);
      SAXIGP1WLAST : in std_ulogic;
      SAXIGP1WSTRB : in std_logic_vector(3 downto 0);
      SAXIGP1WVALID : in std_ulogic;
      SAXIHP0ACLK : in std_ulogic;
      SAXIHP0ARADDR : in std_logic_vector(31 downto 0);
      SAXIHP0ARBURST : in std_logic_vector(1 downto 0);
      SAXIHP0ARCACHE : in std_logic_vector(3 downto 0);
      SAXIHP0ARID : in std_logic_vector(5 downto 0);
      SAXIHP0ARLEN : in std_logic_vector(3 downto 0);
      SAXIHP0ARLOCK : in std_logic_vector(1 downto 0);
      SAXIHP0ARPROT : in std_logic_vector(2 downto 0);
      SAXIHP0ARQOS : in std_logic_vector(3 downto 0);
      SAXIHP0ARSIZE : in std_logic_vector(1 downto 0);
      SAXIHP0ARVALID : in std_ulogic;
      SAXIHP0AWADDR : in std_logic_vector(31 downto 0);
      SAXIHP0AWBURST : in std_logic_vector(1 downto 0);
      SAXIHP0AWCACHE : in std_logic_vector(3 downto 0);
      SAXIHP0AWID : in std_logic_vector(5 downto 0);
      SAXIHP0AWLEN : in std_logic_vector(3 downto 0);
      SAXIHP0AWLOCK : in std_logic_vector(1 downto 0);
      SAXIHP0AWPROT : in std_logic_vector(2 downto 0);
      SAXIHP0AWQOS : in std_logic_vector(3 downto 0);
      SAXIHP0AWSIZE : in std_logic_vector(1 downto 0);
      SAXIHP0AWVALID : in std_ulogic;
      SAXIHP0BREADY : in std_ulogic;
      SAXIHP0RDISSUECAP1EN : in std_ulogic;
      SAXIHP0RREADY : in std_ulogic;
      SAXIHP0WDATA : in std_logic_vector(63 downto 0);
      SAXIHP0WID : in std_logic_vector(5 downto 0);
      SAXIHP0WLAST : in std_ulogic;
      SAXIHP0WRISSUECAP1EN : in std_ulogic;
      SAXIHP0WSTRB : in std_logic_vector(7 downto 0);
      SAXIHP0WVALID : in std_ulogic;
      SAXIHP1ACLK : in std_ulogic;
      SAXIHP1ARADDR : in std_logic_vector(31 downto 0);
      SAXIHP1ARBURST : in std_logic_vector(1 downto 0);
      SAXIHP1ARCACHE : in std_logic_vector(3 downto 0);
      SAXIHP1ARID : in std_logic_vector(5 downto 0);
      SAXIHP1ARLEN : in std_logic_vector(3 downto 0);
      SAXIHP1ARLOCK : in std_logic_vector(1 downto 0);
      SAXIHP1ARPROT : in std_logic_vector(2 downto 0);
      SAXIHP1ARQOS : in std_logic_vector(3 downto 0);
      SAXIHP1ARSIZE : in std_logic_vector(1 downto 0);
      SAXIHP1ARVALID : in std_ulogic;
      SAXIHP1AWADDR : in std_logic_vector(31 downto 0);
      SAXIHP1AWBURST : in std_logic_vector(1 downto 0);
      SAXIHP1AWCACHE : in std_logic_vector(3 downto 0);
      SAXIHP1AWID : in std_logic_vector(5 downto 0);
      SAXIHP1AWLEN : in std_logic_vector(3 downto 0);
      SAXIHP1AWLOCK : in std_logic_vector(1 downto 0);
      SAXIHP1AWPROT : in std_logic_vector(2 downto 0);
      SAXIHP1AWQOS : in std_logic_vector(3 downto 0);
      SAXIHP1AWSIZE : in std_logic_vector(1 downto 0);
      SAXIHP1AWVALID : in std_ulogic;
      SAXIHP1BREADY : in std_ulogic;
      SAXIHP1RDISSUECAP1EN : in std_ulogic;
      SAXIHP1RREADY : in std_ulogic;
      SAXIHP1WDATA : in std_logic_vector(63 downto 0);
      SAXIHP1WID : in std_logic_vector(5 downto 0);
      SAXIHP1WLAST : in std_ulogic;
      SAXIHP1WRISSUECAP1EN : in std_ulogic;
      SAXIHP1WSTRB : in std_logic_vector(7 downto 0);
      SAXIHP1WVALID : in std_ulogic;
      SAXIHP2ACLK : in std_ulogic;
      SAXIHP2ARADDR : in std_logic_vector(31 downto 0);
      SAXIHP2ARBURST : in std_logic_vector(1 downto 0);
      SAXIHP2ARCACHE : in std_logic_vector(3 downto 0);
      SAXIHP2ARID : in std_logic_vector(5 downto 0);
      SAXIHP2ARLEN : in std_logic_vector(3 downto 0);
      SAXIHP2ARLOCK : in std_logic_vector(1 downto 0);
      SAXIHP2ARPROT : in std_logic_vector(2 downto 0);
      SAXIHP2ARQOS : in std_logic_vector(3 downto 0);
      SAXIHP2ARSIZE : in std_logic_vector(1 downto 0);
      SAXIHP2ARVALID : in std_ulogic;
      SAXIHP2AWADDR : in std_logic_vector(31 downto 0);
      SAXIHP2AWBURST : in std_logic_vector(1 downto 0);
      SAXIHP2AWCACHE : in std_logic_vector(3 downto 0);
      SAXIHP2AWID : in std_logic_vector(5 downto 0);
      SAXIHP2AWLEN : in std_logic_vector(3 downto 0);
      SAXIHP2AWLOCK : in std_logic_vector(1 downto 0);
      SAXIHP2AWPROT : in std_logic_vector(2 downto 0);
      SAXIHP2AWQOS : in std_logic_vector(3 downto 0);
      SAXIHP2AWSIZE : in std_logic_vector(1 downto 0);
      SAXIHP2AWVALID : in std_ulogic;
      SAXIHP2BREADY : in std_ulogic;
      SAXIHP2RDISSUECAP1EN : in std_ulogic;
      SAXIHP2RREADY : in std_ulogic;
      SAXIHP2WDATA : in std_logic_vector(63 downto 0);
      SAXIHP2WID : in std_logic_vector(5 downto 0);
      SAXIHP2WLAST : in std_ulogic;
      SAXIHP2WRISSUECAP1EN : in std_ulogic;
      SAXIHP2WSTRB : in std_logic_vector(7 downto 0);
      SAXIHP2WVALID : in std_ulogic;
      SAXIHP3ACLK : in std_ulogic;
      SAXIHP3ARADDR : in std_logic_vector(31 downto 0);
      SAXIHP3ARBURST : in std_logic_vector(1 downto 0);
      SAXIHP3ARCACHE : in std_logic_vector(3 downto 0);
      SAXIHP3ARID : in std_logic_vector(5 downto 0);
      SAXIHP3ARLEN : in std_logic_vector(3 downto 0);
      SAXIHP3ARLOCK : in std_logic_vector(1 downto 0);
      SAXIHP3ARPROT : in std_logic_vector(2 downto 0);
      SAXIHP3ARQOS : in std_logic_vector(3 downto 0);
      SAXIHP3ARSIZE : in std_logic_vector(1 downto 0);
      SAXIHP3ARVALID : in std_ulogic;
      SAXIHP3AWADDR : in std_logic_vector(31 downto 0);
      SAXIHP3AWBURST : in std_logic_vector(1 downto 0);
      SAXIHP3AWCACHE : in std_logic_vector(3 downto 0);
      SAXIHP3AWID : in std_logic_vector(5 downto 0);
      SAXIHP3AWLEN : in std_logic_vector(3 downto 0);
      SAXIHP3AWLOCK : in std_logic_vector(1 downto 0);
      SAXIHP3AWPROT : in std_logic_vector(2 downto 0);
      SAXIHP3AWQOS : in std_logic_vector(3 downto 0);
      SAXIHP3AWSIZE : in std_logic_vector(1 downto 0);
      SAXIHP3AWVALID : in std_ulogic;
      SAXIHP3BREADY : in std_ulogic;
      SAXIHP3RDISSUECAP1EN : in std_ulogic;
      SAXIHP3RREADY : in std_ulogic;
      SAXIHP3WDATA : in std_logic_vector(63 downto 0);
      SAXIHP3WID : in std_logic_vector(5 downto 0);
      SAXIHP3WLAST : in std_ulogic;
      SAXIHP3WRISSUECAP1EN : in std_ulogic;
      SAXIHP3WSTRB : in std_logic_vector(7 downto 0);
      SAXIHP3WVALID : in std_ulogic
      );
  end component;
  attribute BOX_TYPE of
    PS7 : component is "PRIMITIVE";

  -- AXI3 signals, as the PS7 primitive has them, sized for the widest
  -- of all AXI ports.  Each port uses the LSBs it has.
  constant ps_id_width_c : natural := 12;
  constant ps_data_width_c : natural := 64;
  constant ps_user_width_c : natural := 5;

  type ps_addr_t is
  record
    addr: std_logic_vector(31 downto 0);
    burst: std_logic_vector(1 downto 0);
    cache: std_logic_vector(3 downto 0);
    id: std_logic_vector(ps_id_width_c-1 downto 0);
    len: std_logic_vector(3 downto 0);
    lock: std_logic_vector(1 downto 0);
    prot: std_logic_vector(2 downto 0);
    qos: std_logic_vector(3 downto 0);
    size: std_logic_vector(1 downto 0);
    user: std_logic_vector(ps_user_width_c-1 downto 0);
    valid: std_ulogic;
  end record;

  -- Master-driven AXI3 signals.
  type ps_fwd_t is
  record
    aw: ps_addr_t;
    ar: ps_addr_t;
    wdata: std_logic_vector(ps_data_width_c-1 downto 0);
    wid: std_logic_vector(ps_id_width_c-1 downto 0);
    wlast: std_ulogic;
    wstrb: std_logic_vector(ps_data_width_c/8-1 downto 0);
    wvalid: std_ulogic;
    bready: std_ulogic;
    rready: std_ulogic;
  end record;

  -- Slave-driven AXI3 signals.
  type ps_bwd_t is
  record
    awready: std_ulogic;
    arready: std_ulogic;
    wready: std_ulogic;
    bid: std_logic_vector(ps_id_width_c-1 downto 0);
    bresp: std_logic_vector(1 downto 0);
    bvalid: std_ulogic;
    rdata: std_logic_vector(ps_data_width_c-1 downto 0);
    rid: std_logic_vector(ps_id_width_c-1 downto 0);
    rlast: std_ulogic;
    rresp: std_logic_vector(1 downto 0);
    rvalid: std_ulogic;
  end record;

  type ps_fwd_vector is array (natural range <>) of ps_fwd_t;
  type ps_bwd_vector is array (natural range <>) of ps_bwd_t;

  type dma_ps_i_t is
  record
    drvalid: std_ulogic;
    drtype: std_logic_vector(1 downto 0);
    drlast: std_ulogic;
    daready: std_ulogic;
  end record;

  type dma_ps_o_t is
  record
    drready: std_ulogic;
    davalid: std_ulogic;
    datype: std_logic_vector(1 downto 0);
  end record;

  type dma_ps_i_vector is array (natural range <>) of dma_ps_i_t;
  type dma_ps_o_vector is array (natural range <>) of dma_ps_o_t;

  function to_lock(l: std_logic_vector(1 downto 0)) return lock_enum_t
  is
  begin
    if l(0) = '1' then
      return LOCK_EXCLUSIVE;
    end if;
    return LOCK_NORMAL;
  end function;

  function data_width(cfg: config_t) return natural
  is
  begin
    return 8 * 2 ** cfg.data_bus_width_l2;
  end function;

  -- Checks an NSL config of a port where PS is master can be derived
  -- from native one without losing anything but address MSBs.
  function m_config_check(name: string; cfg, native: config_t) return boolean
  is
  begin
    assert cfg.data_bus_width_l2 = native.data_bus_width_l2
      report name & ": data width must be " & integer'image(data_width(native))
      severity failure;
    assert cfg.address_width <= 32
      report name & ": address width must be 32 or less"
      severity failure;
    assert cfg.id_width >= native.id_width
      report name & ": ID width must be " & integer'image(native.id_width) & " or more"
      severity failure;
    assert cfg.len_width >= native.len_width
      report name & ": max_length must be " & integer'image(2 ** native.len_width) & " or more"
      severity failure;
    assert cfg.has_size and cfg.has_burst
      report name & ": size and burst are mandatory"
      severity failure;
    return true;
  end function;

  -- Checks an NSL config of a port where PS is slave is a subset of
  -- native one.  data_width_l2_min allows narrower data than native.
  function s_config_check(name: string; cfg, native: config_t;
                          data_width_l2_min: natural) return boolean
  is
  begin
    assert cfg.data_bus_width_l2 >= data_width_l2_min
      and cfg.data_bus_width_l2 <= native.data_bus_width_l2
      report name & ": unsupported data width"
      severity failure;
    assert cfg.address_width <= 32
      report name & ": address width must be 32 or less"
      severity failure;
    assert cfg.id_width <= native.id_width
      report name & ": ID width must be " & integer'image(native.id_width) & " or less"
      severity failure;
    assert cfg.len_width <= native.len_width
      report name & ": max_length must be " & integer'image(2 ** native.len_width) & " or less"
      severity failure;
    assert native.user_width = 0 or cfg.user_width <= native.user_width
      report name & ": user width must be " & integer'image(native.user_width) & " or less"
      severity failure;
    return true;
  end function;

  -- M_AXI_*: PS address to NSL
  function to_address(cfg: config_t; a: ps_addr_t) return address_t
  is
  begin
    return address(cfg,
                   id => std_ulogic_vector(resize(unsigned(a.id), cfg.id_width)),
                   addr => resize(unsigned(a.addr), cfg.address_width),
                   len_m1 => resize(unsigned(a.len), cfg.len_width),
                   size_l2 => unsigned('0' & a.size),
                   burst => to_burst(cfg, std_ulogic_vector(a.burst)),
                   lock => to_lock(a.lock),
                   cache => std_ulogic_vector(a.cache),
                   prot => std_ulogic_vector(a.prot),
                   qos => std_ulogic_vector(a.qos),
                   valid => a.valid = '1');
  end function;

  -- S_AXI_*: NSL address to PS.  User is only meaningful for ACP,
  -- where the native config bounds it.
  function to_ps_addr(cfg: config_t; a: address_t) return ps_addr_t
  is
    variable ret: ps_addr_t;
    variable size: unsigned(2 downto 0);
    variable u: std_ulogic_vector(cfg.user_width-1 downto 0);
  begin
    size := size_l2(cfg, a);
    u := user(cfg, a);
    ret.addr := std_logic_vector(resize(address(cfg, a), ret.addr'length));
    ret.burst := std_logic_vector(to_logic(cfg, burst(cfg, a)));
    ret.cache := std_logic_vector(cache(cfg, a));
    ret.id := std_logic_vector(resize(unsigned(id(cfg, a)), ret.id'length));
    ret.len := std_logic_vector(length_m1(cfg, a, ret.len'length));
    ret.lock := '0' & std_logic_vector(to_logic(cfg, lock(cfg, a)));
    ret.prot := std_logic_vector(prot(cfg, a));
    ret.qos := std_logic_vector(qos(cfg, a));
    ret.size := std_logic_vector(size(1 downto 0));
    ret.user := (others => '0');
    for i in u'range
    loop
      if i < ret.user'length then
        ret.user(i) := u(i);
      end if;
    end loop;
    ret.valid := a.valid;
    return ret;
  end function;

  -- M_AXI_*: PS master signals to NSL master record
  function to_master(cfg: config_t; f: ps_fwd_t) return master_t
  is
    constant dw: natural := data_width(cfg);
  begin
    return (
      aw => to_address(cfg, f.aw),
      ar => to_address(cfg, f.ar),
      w => write_data(cfg,
                      value => unsigned(f.wdata(dw-1 downto 0)),
                      strb => std_ulogic_vector(f.wstrb(dw/8-1 downto 0)),
                      endian => ENDIAN_LITTLE,
                      last => f.wlast = '1',
                      valid => f.wvalid = '1'),
      b => accept(cfg, f.bready = '1'),
      r => accept(cfg, f.rready = '1')
      );
  end function;

  -- M_AXI_*: NSL slave record to PS slave signals.  IDs are truncated
  -- back to native width, the slave only answers with IDs it got.
  function to_ps_bwd(cfg: config_t; s: slave_t) return ps_bwd_t
  is
    constant dw: natural := data_width(cfg);
    variable ret: ps_bwd_t;
  begin
    ret.awready := s.aw.ready;
    ret.arready := s.ar.ready;
    ret.wready := s.w.ready;
    ret.bid := std_logic_vector(resize(unsigned(id(cfg, s.b)), ret.bid'length));
    ret.bresp := std_logic_vector(to_logic(cfg, resp(cfg, s.b)));
    ret.bvalid := s.b.valid;
    ret.rdata := (others => '0');
    ret.rdata(dw-1 downto 0) := std_logic_vector(value(cfg, s.r, ENDIAN_LITTLE));
    ret.rid := std_logic_vector(resize(unsigned(id(cfg, s.r)), ret.rid'length));
    ret.rlast := '0';
    if is_last(cfg, s.r) then
      ret.rlast := '1';
    end if;
    ret.rresp := std_logic_vector(to_logic(cfg, resp(cfg, s.r)));
    ret.rvalid := s.r.valid;
    return ret;
  end function;

  -- S_AXI_*: NSL master record to PS master signals.  WID is left
  -- to the caller.
  function to_ps_fwd(cfg: config_t; m: master_t) return ps_fwd_t
  is
    constant dw: natural := data_width(cfg);
    variable ret: ps_fwd_t;
  begin
    ret.aw := to_ps_addr(cfg, m.aw);
    ret.ar := to_ps_addr(cfg, m.ar);
    ret.wdata := (others => '0');
    ret.wdata(dw-1 downto 0) := std_logic_vector(value(cfg, m.w, ENDIAN_LITTLE));
    ret.wid := (others => '0');
    ret.wlast := '0';
    if is_last(cfg, m.w) then
      ret.wlast := '1';
    end if;
    ret.wstrb := (others => '0');
    ret.wstrb(dw/8-1 downto 0) := std_logic_vector(bitswap(strb(cfg, m.w)));
    ret.wvalid := m.w.valid;
    ret.bready := m.b.ready;
    ret.rready := m.r.ready;
    return ret;
  end function;

  -- S_AXI_*: PS slave signals to NSL slave record
  function to_slave(cfg: config_t; b: ps_bwd_t) return slave_t
  is
    constant dw: natural := data_width(cfg);
    variable ret: slave_t;
  begin
    ret.aw := accept(cfg, b.awready = '1');
    ret.ar := accept(cfg, b.arready = '1');
    ret.w := accept(cfg, b.wready = '1');
    ret.b := write_response(cfg,
                            id => std_ulogic_vector(resize(unsigned(b.bid), cfg.id_width)),
                            resp => to_resp(cfg, std_ulogic_vector(b.bresp)),
                            valid => b.bvalid = '1');
    ret.r := read_data(cfg,
                       id => std_ulogic_vector(resize(unsigned(b.rid), cfg.id_width)),
                       value => unsigned(b.rdata(dw-1 downto 0)),
                       endian => ENDIAN_LITTLE,
                       resp => to_resp(cfg, std_ulogic_vector(b.rresp)),
                       last => b.rlast = '1',
                       valid => b.rvalid = '1');
    return ret;
  end function;

  constant m_gp_config_c : config_vector(0 to 1)
    := (m_axi_gp0_config_c, m_axi_gp1_config_c);
  -- S_AXI ports: GP0, GP1, HP0 to HP3, ACP
  constant s_config_c : config_vector(0 to 6)
    := (s_axi_gp0_config_c, s_axi_gp1_config_c,
        s_axi_hp0_config_c, s_axi_hp1_config_c,
        s_axi_hp2_config_c, s_axi_hp3_config_c,
        s_axi_acp_config_c);
  constant s_native_config_c : config_vector(0 to 6)
    := (s_axi_gp_config_c, s_axi_gp_config_c,
        s_axi_hp_config_c, s_axi_hp_config_c,
        s_axi_hp_config_c, s_axi_hp_config_c,
        nsl_xilinx.ps7.s_axi_acp_config_c);
  type natural_vector is array (integer range <>) of natural;
  constant s_write_acceptance_c : natural_vector(0 to 6)
    := (ps7_s_axi_gp_write_acceptance_c, ps7_s_axi_gp_write_acceptance_c,
        ps7_s_axi_hp_write_acceptance_c, ps7_s_axi_hp_write_acceptance_c,
        ps7_s_axi_hp_write_acceptance_c, ps7_s_axi_hp_write_acceptance_c,
        ps7_s_axi_acp_write_acceptance_c);
  constant m_gp0_ok_c : boolean
    := m_config_check("M_AXI_GP0", m_axi_gp0_config_c, m_axi_gp_config_c);
  constant m_gp1_ok_c : boolean
    := m_config_check("M_AXI_GP1", m_axi_gp1_config_c, m_axi_gp_config_c);
  constant s_gp0_ok_c : boolean
    := s_config_check("S_AXI_GP0", s_axi_gp0_config_c, s_axi_gp_config_c,
                      s_axi_gp_config_c.data_bus_width_l2);
  constant s_gp1_ok_c : boolean
    := s_config_check("S_AXI_GP1", s_axi_gp1_config_c, s_axi_gp_config_c,
                      s_axi_gp_config_c.data_bus_width_l2);

  constant s_hp0_ok_c : boolean
    := s_config_check("S_AXI_HP0", s_axi_hp0_config_c, s_axi_hp_config_c, 2);
  constant s_hp1_ok_c : boolean
    := s_config_check("S_AXI_HP1", s_axi_hp1_config_c, s_axi_hp_config_c, 2);
  constant s_hp2_ok_c : boolean
    := s_config_check("S_AXI_HP2", s_axi_hp2_config_c, s_axi_hp_config_c, 2);
  constant s_hp3_ok_c : boolean
    := s_config_check("S_AXI_HP3", s_axi_hp3_config_c, s_axi_hp_config_c, 2);
  constant s_acp_ok_c : boolean
    := s_config_check("S_AXI_ACP", s_axi_acp_config_c,
                      nsl_xilinx.ps7.s_axi_acp_config_c, 3);

  -- Hexadecimal digits of v, MSB first, only for values below 2**31.
  function hex(v: natural; digits: positive) return string
  is
    constant digits_c : string(1 to 16) := "0123456789ABCDEF";
    variable ret : string(1 to digits);
    variable x : natural := v;
  begin
    for i in digits downto 1
    loop
      ret(i) := digits_c(x mod 16 + 1);
      x := x / 16;
    end loop;
    return ret;
  end function;

  -- Registers reported are all in the 0xF8000000 to 0xF8FFFFFF range,
  -- address is relative to it, so that it fits in a natural.
  function register_note(address, mask, value: natural; comment: string)
    return string
  is
  begin
    return "nsl_xilinx.ps7: write 0xF8" & hex(address, 6)
      & " mask 0x" & hex(mask, 8) & " value 0x" & hex(value, 8)
      & " # " & comment;
  end function;

  function to_natural(b: boolean) return natural
  is
  begin
    if b then
      return 1;
    end if;
    return 0;
  end function;

  constant slcr_lvl_shftr_en_c : natural := 16#000900#;
  constant afi_base_c : natural := 16#008000#;
  constant afi_stride_c : natural := 16#1000#;
  constant afi_rdchan_ctrl_c : natural := 16#00#;
  constant afi_wrchan_ctrl_c : natural := 16#14#;

  -- AFI FIFO levels, as the PS7 primitive has them.
  type hp_ps_level_t is
  record
    rcount: std_logic_vector(7 downto 0);
    wcount: std_logic_vector(7 downto 0);
    racount: std_logic_vector(2 downto 0);
    wacount: std_logic_vector(5 downto 0);
  end record;
  type hp_ps_level_vector is array (natural range <>) of hp_ps_level_t;

  signal m_aclk, m_aresetn: std_ulogic_vector(0 to 1);
  signal m_fwd: ps_fwd_vector(0 to 1);
  signal m_bwd: ps_bwd_vector(0 to 1);
  signal m_o: master_vector(0 to 1);
  signal m_i: slave_vector(0 to 1);
  signal s_aclk, s_aresetn: std_ulogic_vector(0 to 6);
  signal s_fwd: ps_fwd_vector(0 to 6);
  signal s_bwd: ps_bwd_vector(0 to 6);
  signal s_i: master_vector(0 to 6);
  signal s_o: slave_vector(0 to 6);
  signal hp_level: hp_ps_level_vector(0 to 3);
  signal hp_rd_issue_cap1, hp_wr_issue_cap1: std_ulogic_vector(0 to 3);
  signal dma_ps_i: dma_ps_i_vector(0 to 3);
  signal dma_ps_o: dma_ps_o_vector(0 to 3);
  signal fclk_s, fclk_reset_n_s: std_logic_vector(3 downto 0);
  signal irq_p2f_s: std_logic_vector(28 downto 0);
  signal irq_f2p_s: std_logic_vector(19 downto 0);
  signal gem0_gmii_txd_s, gem0_gmii_rxd_s: std_logic_vector(7 downto 0);
  signal i2c0_scl_o_s, i2c0_scl_tn_s, i2c0_sda_o_s, i2c0_sda_tn_s: std_ulogic;
  signal spi0_mo_s, spi0_motn_s, spi0_sclko_s, spi0_ssntn_s, spi0_mi_s: std_ulogic;
  signal spi0_sson_s: std_logic_vector(2 downto 0);
  signal spi0_selected_s: std_ulogic_vector(0 to spi0_slave_count_c-1);
  signal uart0_dtrn_s, uart0_rtsn_s, uart0_ctsn_s, uart0_dcdn_s, uart0_dsrn_s, uart0_rin_s: std_ulogic;
  signal gem1_gmii_txd_s, gem1_gmii_rxd_s: std_logic_vector(7 downto 0);
  signal i2c1_scl_o_s, i2c1_scl_tn_s, i2c1_sda_o_s, i2c1_sda_tn_s: std_ulogic;
  signal spi1_mo_s, spi1_motn_s, spi1_sclko_s, spi1_ssntn_s, spi1_mi_s: std_ulogic;
  signal spi1_sson_s: std_logic_vector(2 downto 0);
  signal spi1_selected_s: std_ulogic_vector(0 to spi1_slave_count_c-1);
  signal uart1_dtrn_s, uart1_rtsn_s, uart1_ctsn_s, uart1_dcdn_s, uart1_dsrn_s, uart1_rin_s: std_ulogic;
  signal gpio_o_s, gpio_tn_s, gpio_i_s: std_logic_vector(63 downto 0);

  -- Whether slave index_c is selected, given PS7 SS outputs.  In
  -- decoded mode, SS outputs carry a slave index, "111" selects none.
  function spi_selected(sson: std_logic_vector(2 downto 0);
                        ssntn: std_ulogic;
                        decoded: boolean;
                        index: natural) return std_ulogic
  is
  begin
    if ssntn /= '1' then
      return '0';
    elsif decoded then
      if to_integer(unsigned(sson)) = index then
        return '1';
      else
        return '0';
      end if;
    else
      return not sson(index);
    end if;
  end function;

  function spi_miso(selected: std_ulogic_vector;
                    slaves: nsl_spi.spi.spi_master_i_vector) return std_ulogic
  is
    variable ret: std_ulogic := '1';
  begin
    for i in selected'range
    loop
      if selected(i) = '1' then
        ret := slaves(i).miso;
      end if;
    end loop;
    return ret;
  end function;

begin

  ps: PS7
    port map(
      DMA0DATYPE => dma_ps_o(0).datype,
      DMA0DAVALID => dma_ps_o(0).davalid,
      DMA0DRREADY => dma_ps_o(0).drready,
      DMA0RSTN => dmac_reset_n_o(0),
      DMA1DATYPE => dma_ps_o(1).datype,
      DMA1DAVALID => dma_ps_o(1).davalid,
      DMA1DRREADY => dma_ps_o(1).drready,
      DMA1RSTN => dmac_reset_n_o(1),
      DMA2DATYPE => dma_ps_o(2).datype,
      DMA2DAVALID => dma_ps_o(2).davalid,
      DMA2DRREADY => dma_ps_o(2).drready,
      DMA2RSTN => dmac_reset_n_o(2),
      DMA3DATYPE => dma_ps_o(3).datype,
      DMA3DAVALID => dma_ps_o(3).davalid,
      DMA3DRREADY => dma_ps_o(3).drready,
      DMA3RSTN => dmac_reset_n_o(3),
      EMIOCAN0PHYTX => open,
      EMIOCAN1PHYTX => open,
      EMIOENET0GMIITXD => gem0_gmii_txd_s,
      EMIOENET0GMIITXEN => gem0_gmii_tx_o.en,
      EMIOENET0GMIITXER => gem0_gmii_tx_o.er,
      EMIOENET0MDIOMDC => gem0_smi_o.mdc,
      EMIOENET0MDIOO => gem0_smi_o.mdio.v,
      EMIOENET0MDIOTN => gem0_smi_o.mdio.output,
      EMIOENET0PTPDELAYREQRX => gem0_ptp_rx_o.delay_req,
      EMIOENET0PTPDELAYREQTX => gem0_ptp_tx_o.delay_req,
      EMIOENET0PTPPDELAYREQRX => gem0_ptp_rx_o.pdelay_req,
      EMIOENET0PTPPDELAYREQTX => gem0_ptp_tx_o.pdelay_req,
      EMIOENET0PTPPDELAYRESPRX => gem0_ptp_rx_o.pdelay_resp,
      EMIOENET0PTPPDELAYRESPTX => gem0_ptp_tx_o.pdelay_resp,
      EMIOENET0PTPSYNCFRAMERX => gem0_ptp_rx_o.sync,
      EMIOENET0PTPSYNCFRAMETX => gem0_ptp_tx_o.sync,
      EMIOENET0SOFRX => gem0_ptp_rx_o.sof,
      EMIOENET0SOFTX => gem0_ptp_tx_o.sof,
      EMIOENET1GMIITXD => gem1_gmii_txd_s,
      EMIOENET1GMIITXEN => gem1_gmii_tx_o.en,
      EMIOENET1GMIITXER => gem1_gmii_tx_o.er,
      EMIOENET1MDIOMDC => gem1_smi_o.mdc,
      EMIOENET1MDIOO => gem1_smi_o.mdio.v,
      EMIOENET1MDIOTN => gem1_smi_o.mdio.output,
      EMIOENET1PTPDELAYREQRX => gem1_ptp_rx_o.delay_req,
      EMIOENET1PTPDELAYREQTX => gem1_ptp_tx_o.delay_req,
      EMIOENET1PTPPDELAYREQRX => gem1_ptp_rx_o.pdelay_req,
      EMIOENET1PTPPDELAYREQTX => gem1_ptp_tx_o.pdelay_req,
      EMIOENET1PTPPDELAYRESPRX => gem1_ptp_rx_o.pdelay_resp,
      EMIOENET1PTPPDELAYRESPTX => gem1_ptp_tx_o.pdelay_resp,
      EMIOENET1PTPSYNCFRAMERX => gem1_ptp_rx_o.sync,
      EMIOENET1PTPSYNCFRAMETX => gem1_ptp_tx_o.sync,
      EMIOENET1SOFRX => gem1_ptp_rx_o.sof,
      EMIOENET1SOFTX => gem1_ptp_tx_o.sof,
      EMIOGPIOO => gpio_o_s,
      EMIOGPIOTN => gpio_tn_s,
      EMIOI2C0SCLO => i2c0_scl_o_s,
      EMIOI2C0SCLTN => i2c0_scl_tn_s,
      EMIOI2C0SDAO => i2c0_sda_o_s,
      EMIOI2C0SDATN => i2c0_sda_tn_s,
      EMIOI2C1SCLO => i2c1_scl_o_s,
      EMIOI2C1SCLTN => i2c1_scl_tn_s,
      EMIOI2C1SDAO => i2c1_sda_o_s,
      EMIOI2C1SDATN => i2c1_sda_tn_s,
      EMIOPJTAGTDO => open,
      EMIOPJTAGTDTN => open,
      EMIOSDIO0BUSPOW => open,
      EMIOSDIO0BUSVOLT => open,
      EMIOSDIO0CLK => open,
      EMIOSDIO0CMDO => open,
      EMIOSDIO0CMDTN => open,
      EMIOSDIO0DATAO => open,
      EMIOSDIO0DATATN => open,
      EMIOSDIO0LED => open,
      EMIOSDIO1BUSPOW => open,
      EMIOSDIO1BUSVOLT => open,
      EMIOSDIO1CLK => open,
      EMIOSDIO1CMDO => open,
      EMIOSDIO1CMDTN => open,
      EMIOSDIO1DATAO => open,
      EMIOSDIO1DATATN => open,
      EMIOSDIO1LED => open,
      EMIOSPI0MO => spi0_mo_s,
      EMIOSPI0MOTN => spi0_motn_s,
      EMIOSPI0SCLKO => spi0_sclko_s,
      EMIOSPI0SCLKTN => open,
      EMIOSPI0SO => open,
      EMIOSPI0SSNTN => spi0_ssntn_s,
      EMIOSPI0SSON => spi0_sson_s,
      EMIOSPI0STN => open,
      EMIOSPI1MO => spi1_mo_s,
      EMIOSPI1MOTN => spi1_motn_s,
      EMIOSPI1SCLKO => spi1_sclko_s,
      EMIOSPI1SCLKTN => open,
      EMIOSPI1SO => open,
      EMIOSPI1SSNTN => spi1_ssntn_s,
      EMIOSPI1SSON => spi1_sson_s,
      EMIOSPI1STN => open,
      EMIOTRACECTL => open,
      EMIOTRACEDATA => open,
      EMIOTTC0WAVEO => open,
      EMIOTTC1WAVEO => open,
      EMIOUART0DTRN => uart0_dtrn_s,
      EMIOUART0RTSN => uart0_rtsn_s,
      EMIOUART0TX => uart0_o.data,
      EMIOUART1DTRN => uart1_dtrn_s,
      EMIOUART1RTSN => uart1_rtsn_s,
      EMIOUART1TX => uart1_o.data,
      EMIOUSB0PORTINDCTL => open,
      EMIOUSB0VBUSPWRSELECT => open,
      EMIOUSB1PORTINDCTL => open,
      EMIOUSB1VBUSPWRSELECT => open,
      EMIOWDTRSTO => open,
      EVENTEVENTO => open,
      EVENTSTANDBYWFE => open,
      EVENTSTANDBYWFI => open,
      FCLKCLK => fclk_s,
      FCLKRESETN => fclk_reset_n_s,
      FTMTF2PTRIGACK => open,
      FTMTP2FDEBUG => open,
      FTMTP2FTRIG => open,
      IRQP2F => irq_p2f_s,
      MAXIGP0ARADDR => m_fwd(0).ar.addr,
      MAXIGP0ARBURST => m_fwd(0).ar.burst,
      MAXIGP0ARCACHE => m_fwd(0).ar.cache,
      MAXIGP0ARESETN => m_aresetn(0),
      MAXIGP0ARID => m_fwd(0).ar.id,
      MAXIGP0ARLEN => m_fwd(0).ar.len,
      MAXIGP0ARLOCK => m_fwd(0).ar.lock,
      MAXIGP0ARPROT => m_fwd(0).ar.prot,
      MAXIGP0ARQOS => m_fwd(0).ar.qos,
      MAXIGP0ARSIZE => m_fwd(0).ar.size,
      MAXIGP0ARVALID => m_fwd(0).ar.valid,
      MAXIGP0AWADDR => m_fwd(0).aw.addr,
      MAXIGP0AWBURST => m_fwd(0).aw.burst,
      MAXIGP0AWCACHE => m_fwd(0).aw.cache,
      MAXIGP0AWID => m_fwd(0).aw.id,
      MAXIGP0AWLEN => m_fwd(0).aw.len,
      MAXIGP0AWLOCK => m_fwd(0).aw.lock,
      MAXIGP0AWPROT => m_fwd(0).aw.prot,
      MAXIGP0AWQOS => m_fwd(0).aw.qos,
      MAXIGP0AWSIZE => m_fwd(0).aw.size,
      MAXIGP0AWVALID => m_fwd(0).aw.valid,
      MAXIGP0BREADY => m_fwd(0).bready,
      MAXIGP0RREADY => m_fwd(0).rready,
      MAXIGP0WDATA => m_fwd(0).wdata(31 downto 0),
      MAXIGP0WID => m_fwd(0).wid,
      MAXIGP0WLAST => m_fwd(0).wlast,
      MAXIGP0WSTRB => m_fwd(0).wstrb(3 downto 0),
      MAXIGP0WVALID => m_fwd(0).wvalid,
      MAXIGP1ARADDR => m_fwd(1).ar.addr,
      MAXIGP1ARBURST => m_fwd(1).ar.burst,
      MAXIGP1ARCACHE => m_fwd(1).ar.cache,
      MAXIGP1ARESETN => m_aresetn(1),
      MAXIGP1ARID => m_fwd(1).ar.id,
      MAXIGP1ARLEN => m_fwd(1).ar.len,
      MAXIGP1ARLOCK => m_fwd(1).ar.lock,
      MAXIGP1ARPROT => m_fwd(1).ar.prot,
      MAXIGP1ARQOS => m_fwd(1).ar.qos,
      MAXIGP1ARSIZE => m_fwd(1).ar.size,
      MAXIGP1ARVALID => m_fwd(1).ar.valid,
      MAXIGP1AWADDR => m_fwd(1).aw.addr,
      MAXIGP1AWBURST => m_fwd(1).aw.burst,
      MAXIGP1AWCACHE => m_fwd(1).aw.cache,
      MAXIGP1AWID => m_fwd(1).aw.id,
      MAXIGP1AWLEN => m_fwd(1).aw.len,
      MAXIGP1AWLOCK => m_fwd(1).aw.lock,
      MAXIGP1AWPROT => m_fwd(1).aw.prot,
      MAXIGP1AWQOS => m_fwd(1).aw.qos,
      MAXIGP1AWSIZE => m_fwd(1).aw.size,
      MAXIGP1AWVALID => m_fwd(1).aw.valid,
      MAXIGP1BREADY => m_fwd(1).bready,
      MAXIGP1RREADY => m_fwd(1).rready,
      MAXIGP1WDATA => m_fwd(1).wdata(31 downto 0),
      MAXIGP1WID => m_fwd(1).wid,
      MAXIGP1WLAST => m_fwd(1).wlast,
      MAXIGP1WSTRB => m_fwd(1).wstrb(3 downto 0),
      MAXIGP1WVALID => m_fwd(1).wvalid,
      SAXIACPARESETN => s_aresetn(6),
      SAXIACPARREADY => s_bwd(6).arready,
      SAXIACPAWREADY => s_bwd(6).awready,
      SAXIACPBID => s_bwd(6).bid(2 downto 0),
      SAXIACPBRESP => s_bwd(6).bresp,
      SAXIACPBVALID => s_bwd(6).bvalid,
      SAXIACPRDATA => s_bwd(6).rdata,
      SAXIACPRID => s_bwd(6).rid(2 downto 0),
      SAXIACPRLAST => s_bwd(6).rlast,
      SAXIACPRRESP => s_bwd(6).rresp,
      SAXIACPRVALID => s_bwd(6).rvalid,
      SAXIACPWREADY => s_bwd(6).wready,
      SAXIGP0ARESETN => s_aresetn(0),
      SAXIGP0ARREADY => s_bwd(0).arready,
      SAXIGP0AWREADY => s_bwd(0).awready,
      SAXIGP0BID => s_bwd(0).bid(5 downto 0),
      SAXIGP0BRESP => s_bwd(0).bresp,
      SAXIGP0BVALID => s_bwd(0).bvalid,
      SAXIGP0RDATA => s_bwd(0).rdata(31 downto 0),
      SAXIGP0RID => s_bwd(0).rid(5 downto 0),
      SAXIGP0RLAST => s_bwd(0).rlast,
      SAXIGP0RRESP => s_bwd(0).rresp,
      SAXIGP0RVALID => s_bwd(0).rvalid,
      SAXIGP0WREADY => s_bwd(0).wready,
      SAXIGP1ARESETN => s_aresetn(1),
      SAXIGP1ARREADY => s_bwd(1).arready,
      SAXIGP1AWREADY => s_bwd(1).awready,
      SAXIGP1BID => s_bwd(1).bid(5 downto 0),
      SAXIGP1BRESP => s_bwd(1).bresp,
      SAXIGP1BVALID => s_bwd(1).bvalid,
      SAXIGP1RDATA => s_bwd(1).rdata(31 downto 0),
      SAXIGP1RID => s_bwd(1).rid(5 downto 0),
      SAXIGP1RLAST => s_bwd(1).rlast,
      SAXIGP1RRESP => s_bwd(1).rresp,
      SAXIGP1RVALID => s_bwd(1).rvalid,
      SAXIGP1WREADY => s_bwd(1).wready,
      SAXIHP0ARESETN => s_aresetn(2),
      SAXIHP0ARREADY => s_bwd(2).arready,
      SAXIHP0AWREADY => s_bwd(2).awready,
      SAXIHP0BID => s_bwd(2).bid(5 downto 0),
      SAXIHP0BRESP => s_bwd(2).bresp,
      SAXIHP0BVALID => s_bwd(2).bvalid,
      SAXIHP0RACOUNT => hp_level(0).racount,
      SAXIHP0RCOUNT => hp_level(0).rcount,
      SAXIHP0RDATA => s_bwd(2).rdata,
      SAXIHP0RID => s_bwd(2).rid(5 downto 0),
      SAXIHP0RLAST => s_bwd(2).rlast,
      SAXIHP0RRESP => s_bwd(2).rresp,
      SAXIHP0RVALID => s_bwd(2).rvalid,
      SAXIHP0WACOUNT => hp_level(0).wacount,
      SAXIHP0WCOUNT => hp_level(0).wcount,
      SAXIHP0WREADY => s_bwd(2).wready,
      SAXIHP1ARESETN => s_aresetn(3),
      SAXIHP1ARREADY => s_bwd(3).arready,
      SAXIHP1AWREADY => s_bwd(3).awready,
      SAXIHP1BID => s_bwd(3).bid(5 downto 0),
      SAXIHP1BRESP => s_bwd(3).bresp,
      SAXIHP1BVALID => s_bwd(3).bvalid,
      SAXIHP1RACOUNT => hp_level(1).racount,
      SAXIHP1RCOUNT => hp_level(1).rcount,
      SAXIHP1RDATA => s_bwd(3).rdata,
      SAXIHP1RID => s_bwd(3).rid(5 downto 0),
      SAXIHP1RLAST => s_bwd(3).rlast,
      SAXIHP1RRESP => s_bwd(3).rresp,
      SAXIHP1RVALID => s_bwd(3).rvalid,
      SAXIHP1WACOUNT => hp_level(1).wacount,
      SAXIHP1WCOUNT => hp_level(1).wcount,
      SAXIHP1WREADY => s_bwd(3).wready,
      SAXIHP2ARESETN => s_aresetn(4),
      SAXIHP2ARREADY => s_bwd(4).arready,
      SAXIHP2AWREADY => s_bwd(4).awready,
      SAXIHP2BID => s_bwd(4).bid(5 downto 0),
      SAXIHP2BRESP => s_bwd(4).bresp,
      SAXIHP2BVALID => s_bwd(4).bvalid,
      SAXIHP2RACOUNT => hp_level(2).racount,
      SAXIHP2RCOUNT => hp_level(2).rcount,
      SAXIHP2RDATA => s_bwd(4).rdata,
      SAXIHP2RID => s_bwd(4).rid(5 downto 0),
      SAXIHP2RLAST => s_bwd(4).rlast,
      SAXIHP2RRESP => s_bwd(4).rresp,
      SAXIHP2RVALID => s_bwd(4).rvalid,
      SAXIHP2WACOUNT => hp_level(2).wacount,
      SAXIHP2WCOUNT => hp_level(2).wcount,
      SAXIHP2WREADY => s_bwd(4).wready,
      SAXIHP3ARESETN => s_aresetn(5),
      SAXIHP3ARREADY => s_bwd(5).arready,
      SAXIHP3AWREADY => s_bwd(5).awready,
      SAXIHP3BID => s_bwd(5).bid(5 downto 0),
      SAXIHP3BRESP => s_bwd(5).bresp,
      SAXIHP3BVALID => s_bwd(5).bvalid,
      SAXIHP3RACOUNT => hp_level(3).racount,
      SAXIHP3RCOUNT => hp_level(3).rcount,
      SAXIHP3RDATA => s_bwd(5).rdata,
      SAXIHP3RID => s_bwd(5).rid(5 downto 0),
      SAXIHP3RLAST => s_bwd(5).rlast,
      SAXIHP3RRESP => s_bwd(5).rresp,
      SAXIHP3RVALID => s_bwd(5).rvalid,
      SAXIHP3WACOUNT => hp_level(3).wacount,
      SAXIHP3WCOUNT => hp_level(3).wcount,
      SAXIHP3WREADY => s_bwd(5).wready,
      DDRA => open,
      DDRBA => open,
      DDRCASB => open,
      DDRCKE => open,
      DDRCKN => open,
      DDRCKP => open,
      DDRCSB => open,
      DDRDM => open,
      DDRDQ => open,
      DDRDQSN => open,
      DDRDQSP => open,
      DDRDRSTB => open,
      DDRODT => open,
      DDRRASB => open,
      DDRVRN => open,
      DDRVRP => open,
      DDRWEB => open,
      MIO => open,
      PSCLK => open,
      PSPORB => open,
      PSSRSTB => open,
      DDRARB => (others => '0'),
      DMA0ACLK => dmac_clock_i(0),
      DMA0DAREADY => dma_ps_i(0).daready,
      DMA0DRLAST => dma_ps_i(0).drlast,
      DMA0DRTYPE => dma_ps_i(0).drtype,
      DMA0DRVALID => dma_ps_i(0).drvalid,
      DMA1ACLK => dmac_clock_i(1),
      DMA1DAREADY => dma_ps_i(1).daready,
      DMA1DRLAST => dma_ps_i(1).drlast,
      DMA1DRTYPE => dma_ps_i(1).drtype,
      DMA1DRVALID => dma_ps_i(1).drvalid,
      DMA2ACLK => dmac_clock_i(2),
      DMA2DAREADY => dma_ps_i(2).daready,
      DMA2DRLAST => dma_ps_i(2).drlast,
      DMA2DRTYPE => dma_ps_i(2).drtype,
      DMA2DRVALID => dma_ps_i(2).drvalid,
      DMA3ACLK => dmac_clock_i(3),
      DMA3DAREADY => dma_ps_i(3).daready,
      DMA3DRLAST => dma_ps_i(3).drlast,
      DMA3DRTYPE => dma_ps_i(3).drtype,
      DMA3DRVALID => dma_ps_i(3).drvalid,
      EMIOCAN0PHYRX => '0',
      EMIOCAN1PHYRX => '0',
      EMIOENET0EXTINTIN => gem0_ext_int_i,
      EMIOENET0GMIICOL => gem0_gmii_col_i,
      EMIOENET0GMIICRS => gem0_gmii_crs_i,
      EMIOENET0GMIIRXCLK => gem0_gmii_rx_clock_i,
      EMIOENET0GMIIRXD => gem0_gmii_rxd_s,
      EMIOENET0GMIIRXDV => gem0_gmii_rx_i.en,
      EMIOENET0GMIIRXER => gem0_gmii_rx_i.er,
      EMIOENET0GMIITXCLK => gem0_tx_clock_i,
      EMIOENET0MDIOI => gem0_smi_i.mdio,
      EMIOENET1EXTINTIN => gem1_ext_int_i,
      EMIOENET1GMIICOL => gem1_gmii_col_i,
      EMIOENET1GMIICRS => gem1_gmii_crs_i,
      EMIOENET1GMIIRXCLK => gem1_gmii_rx_clock_i,
      EMIOENET1GMIIRXD => gem1_gmii_rxd_s,
      EMIOENET1GMIIRXDV => gem1_gmii_rx_i.en,
      EMIOENET1GMIIRXER => gem1_gmii_rx_i.er,
      EMIOENET1GMIITXCLK => gem1_tx_clock_i,
      EMIOENET1MDIOI => gem1_smi_i.mdio,
      EMIOGPIOI => gpio_i_s,
      EMIOI2C0SCLI => i2c0_i.scl,
      EMIOI2C0SDAI => i2c0_i.sda,
      EMIOI2C1SCLI => i2c1_i.scl,
      EMIOI2C1SDAI => i2c1_i.sda,
      EMIOPJTAGTCK => '0',
      EMIOPJTAGTDI => '0',
      EMIOPJTAGTMS => '0',
      EMIOSDIO0CDN => '0',
      EMIOSDIO0CLKFB => '0',
      EMIOSDIO0CMDI => '0',
      EMIOSDIO0DATAI => (others => '0'),
      EMIOSDIO0WP => '0',
      EMIOSDIO1CDN => '0',
      EMIOSDIO1CLKFB => '0',
      EMIOSDIO1CMDI => '0',
      EMIOSDIO1DATAI => (others => '0'),
      EMIOSDIO1WP => '0',
      EMIOSPI0MI => spi0_mi_s,
      EMIOSPI0SCLKI => '0',
      EMIOSPI0SI => '0',
      EMIOSPI0SSIN => '1',
      EMIOSPI1MI => spi1_mi_s,
      EMIOSPI1SCLKI => '0',
      EMIOSPI1SI => '0',
      EMIOSPI1SSIN => '1',
      EMIOSRAMINTIN => '0',
      EMIOTRACECLK => '0',
      EMIOTTC0CLKI => (others => '0'),
      EMIOTTC1CLKI => (others => '0'),
      EMIOUART0CTSN => uart0_ctsn_s,
      EMIOUART0DCDN => uart0_dcdn_s,
      EMIOUART0DSRN => uart0_dsrn_s,
      EMIOUART0RIN => uart0_rin_s,
      EMIOUART0RX => uart0_i.data,
      EMIOUART1CTSN => uart1_ctsn_s,
      EMIOUART1DCDN => uart1_dcdn_s,
      EMIOUART1DSRN => uart1_dsrn_s,
      EMIOUART1RIN => uart1_rin_s,
      EMIOUART1RX => uart1_i.data,
      EMIOUSB0VBUSPWRFAULT => '0',
      EMIOUSB1VBUSPWRFAULT => '0',
      EMIOWDTCLKI => '0',
      EVENTEVENTI => '0',
      FCLKCLKTRIGN => (others => '0'),
      FPGAIDLEN => '0',
      FTMDTRACEINATID => (others => '0'),
      FTMDTRACEINCLOCK => '0',
      FTMDTRACEINDATA => (others => '0'),
      FTMDTRACEINVALID => '0',
      FTMTF2PDEBUG => (others => '0'),
      FTMTF2PTRIG => (others => '0'),
      FTMTP2FTRIGACK => (others => '0'),
      IRQF2P => irq_f2p_s,
      MAXIGP0ACLK => m_aclk(0),
      MAXIGP0ARREADY => m_bwd(0).arready,
      MAXIGP0AWREADY => m_bwd(0).awready,
      MAXIGP0BID => m_bwd(0).bid,
      MAXIGP0BRESP => m_bwd(0).bresp,
      MAXIGP0BVALID => m_bwd(0).bvalid,
      MAXIGP0RDATA => m_bwd(0).rdata(31 downto 0),
      MAXIGP0RID => m_bwd(0).rid,
      MAXIGP0RLAST => m_bwd(0).rlast,
      MAXIGP0RRESP => m_bwd(0).rresp,
      MAXIGP0RVALID => m_bwd(0).rvalid,
      MAXIGP0WREADY => m_bwd(0).wready,
      MAXIGP1ACLK => m_aclk(1),
      MAXIGP1ARREADY => m_bwd(1).arready,
      MAXIGP1AWREADY => m_bwd(1).awready,
      MAXIGP1BID => m_bwd(1).bid,
      MAXIGP1BRESP => m_bwd(1).bresp,
      MAXIGP1BVALID => m_bwd(1).bvalid,
      MAXIGP1RDATA => m_bwd(1).rdata(31 downto 0),
      MAXIGP1RID => m_bwd(1).rid,
      MAXIGP1RLAST => m_bwd(1).rlast,
      MAXIGP1RRESP => m_bwd(1).rresp,
      MAXIGP1RVALID => m_bwd(1).rvalid,
      MAXIGP1WREADY => m_bwd(1).wready,
      SAXIACPACLK => s_aclk(6),
      SAXIACPARADDR => s_fwd(6).ar.addr,
      SAXIACPARBURST => s_fwd(6).ar.burst,
      SAXIACPARCACHE => s_fwd(6).ar.cache,
      SAXIACPARID => s_fwd(6).ar.id(2 downto 0),
      SAXIACPARLEN => s_fwd(6).ar.len,
      SAXIACPARLOCK => s_fwd(6).ar.lock,
      SAXIACPARPROT => s_fwd(6).ar.prot,
      SAXIACPARQOS => s_fwd(6).ar.qos,
      SAXIACPARSIZE => s_fwd(6).ar.size,
      SAXIACPARUSER => s_fwd(6).ar.user,
      SAXIACPARVALID => s_fwd(6).ar.valid,
      SAXIACPAWADDR => s_fwd(6).aw.addr,
      SAXIACPAWBURST => s_fwd(6).aw.burst,
      SAXIACPAWCACHE => s_fwd(6).aw.cache,
      SAXIACPAWID => s_fwd(6).aw.id(2 downto 0),
      SAXIACPAWLEN => s_fwd(6).aw.len,
      SAXIACPAWLOCK => s_fwd(6).aw.lock,
      SAXIACPAWPROT => s_fwd(6).aw.prot,
      SAXIACPAWQOS => s_fwd(6).aw.qos,
      SAXIACPAWSIZE => s_fwd(6).aw.size,
      SAXIACPAWUSER => s_fwd(6).aw.user,
      SAXIACPAWVALID => s_fwd(6).aw.valid,
      SAXIACPBREADY => s_fwd(6).bready,
      SAXIACPRREADY => s_fwd(6).rready,
      SAXIACPWDATA => s_fwd(6).wdata,
      SAXIACPWID => s_fwd(6).wid(2 downto 0),
      SAXIACPWLAST => s_fwd(6).wlast,
      SAXIACPWSTRB => s_fwd(6).wstrb,
      SAXIACPWVALID => s_fwd(6).wvalid,
      SAXIGP0ACLK => s_aclk(0),
      SAXIGP0ARADDR => s_fwd(0).ar.addr,
      SAXIGP0ARBURST => s_fwd(0).ar.burst,
      SAXIGP0ARCACHE => s_fwd(0).ar.cache,
      SAXIGP0ARID => s_fwd(0).ar.id(5 downto 0),
      SAXIGP0ARLEN => s_fwd(0).ar.len,
      SAXIGP0ARLOCK => s_fwd(0).ar.lock,
      SAXIGP0ARPROT => s_fwd(0).ar.prot,
      SAXIGP0ARQOS => s_fwd(0).ar.qos,
      SAXIGP0ARSIZE => s_fwd(0).ar.size,
      SAXIGP0ARVALID => s_fwd(0).ar.valid,
      SAXIGP0AWADDR => s_fwd(0).aw.addr,
      SAXIGP0AWBURST => s_fwd(0).aw.burst,
      SAXIGP0AWCACHE => s_fwd(0).aw.cache,
      SAXIGP0AWID => s_fwd(0).aw.id(5 downto 0),
      SAXIGP0AWLEN => s_fwd(0).aw.len,
      SAXIGP0AWLOCK => s_fwd(0).aw.lock,
      SAXIGP0AWPROT => s_fwd(0).aw.prot,
      SAXIGP0AWQOS => s_fwd(0).aw.qos,
      SAXIGP0AWSIZE => s_fwd(0).aw.size,
      SAXIGP0AWVALID => s_fwd(0).aw.valid,
      SAXIGP0BREADY => s_fwd(0).bready,
      SAXIGP0RREADY => s_fwd(0).rready,
      SAXIGP0WDATA => s_fwd(0).wdata(31 downto 0),
      SAXIGP0WID => s_fwd(0).wid(5 downto 0),
      SAXIGP0WLAST => s_fwd(0).wlast,
      SAXIGP0WSTRB => s_fwd(0).wstrb(3 downto 0),
      SAXIGP0WVALID => s_fwd(0).wvalid,
      SAXIGP1ACLK => s_aclk(1),
      SAXIGP1ARADDR => s_fwd(1).ar.addr,
      SAXIGP1ARBURST => s_fwd(1).ar.burst,
      SAXIGP1ARCACHE => s_fwd(1).ar.cache,
      SAXIGP1ARID => s_fwd(1).ar.id(5 downto 0),
      SAXIGP1ARLEN => s_fwd(1).ar.len,
      SAXIGP1ARLOCK => s_fwd(1).ar.lock,
      SAXIGP1ARPROT => s_fwd(1).ar.prot,
      SAXIGP1ARQOS => s_fwd(1).ar.qos,
      SAXIGP1ARSIZE => s_fwd(1).ar.size,
      SAXIGP1ARVALID => s_fwd(1).ar.valid,
      SAXIGP1AWADDR => s_fwd(1).aw.addr,
      SAXIGP1AWBURST => s_fwd(1).aw.burst,
      SAXIGP1AWCACHE => s_fwd(1).aw.cache,
      SAXIGP1AWID => s_fwd(1).aw.id(5 downto 0),
      SAXIGP1AWLEN => s_fwd(1).aw.len,
      SAXIGP1AWLOCK => s_fwd(1).aw.lock,
      SAXIGP1AWPROT => s_fwd(1).aw.prot,
      SAXIGP1AWQOS => s_fwd(1).aw.qos,
      SAXIGP1AWSIZE => s_fwd(1).aw.size,
      SAXIGP1AWVALID => s_fwd(1).aw.valid,
      SAXIGP1BREADY => s_fwd(1).bready,
      SAXIGP1RREADY => s_fwd(1).rready,
      SAXIGP1WDATA => s_fwd(1).wdata(31 downto 0),
      SAXIGP1WID => s_fwd(1).wid(5 downto 0),
      SAXIGP1WLAST => s_fwd(1).wlast,
      SAXIGP1WSTRB => s_fwd(1).wstrb(3 downto 0),
      SAXIGP1WVALID => s_fwd(1).wvalid,
      SAXIHP0ACLK => s_aclk(2),
      SAXIHP0ARADDR => s_fwd(2).ar.addr,
      SAXIHP0ARBURST => s_fwd(2).ar.burst,
      SAXIHP0ARCACHE => s_fwd(2).ar.cache,
      SAXIHP0ARID => s_fwd(2).ar.id(5 downto 0),
      SAXIHP0ARLEN => s_fwd(2).ar.len,
      SAXIHP0ARLOCK => s_fwd(2).ar.lock,
      SAXIHP0ARPROT => s_fwd(2).ar.prot,
      SAXIHP0ARQOS => s_fwd(2).ar.qos,
      SAXIHP0ARSIZE => s_fwd(2).ar.size,
      SAXIHP0ARVALID => s_fwd(2).ar.valid,
      SAXIHP0AWADDR => s_fwd(2).aw.addr,
      SAXIHP0AWBURST => s_fwd(2).aw.burst,
      SAXIHP0AWCACHE => s_fwd(2).aw.cache,
      SAXIHP0AWID => s_fwd(2).aw.id(5 downto 0),
      SAXIHP0AWLEN => s_fwd(2).aw.len,
      SAXIHP0AWLOCK => s_fwd(2).aw.lock,
      SAXIHP0AWPROT => s_fwd(2).aw.prot,
      SAXIHP0AWQOS => s_fwd(2).aw.qos,
      SAXIHP0AWSIZE => s_fwd(2).aw.size,
      SAXIHP0AWVALID => s_fwd(2).aw.valid,
      SAXIHP0BREADY => s_fwd(2).bready,
      SAXIHP0RDISSUECAP1EN => hp_rd_issue_cap1(0),
      SAXIHP0RREADY => s_fwd(2).rready,
      SAXIHP0WDATA => s_fwd(2).wdata,
      SAXIHP0WID => s_fwd(2).wid(5 downto 0),
      SAXIHP0WLAST => s_fwd(2).wlast,
      SAXIHP0WRISSUECAP1EN => hp_wr_issue_cap1(0),
      SAXIHP0WSTRB => s_fwd(2).wstrb,
      SAXIHP0WVALID => s_fwd(2).wvalid,
      SAXIHP1ACLK => s_aclk(3),
      SAXIHP1ARADDR => s_fwd(3).ar.addr,
      SAXIHP1ARBURST => s_fwd(3).ar.burst,
      SAXIHP1ARCACHE => s_fwd(3).ar.cache,
      SAXIHP1ARID => s_fwd(3).ar.id(5 downto 0),
      SAXIHP1ARLEN => s_fwd(3).ar.len,
      SAXIHP1ARLOCK => s_fwd(3).ar.lock,
      SAXIHP1ARPROT => s_fwd(3).ar.prot,
      SAXIHP1ARQOS => s_fwd(3).ar.qos,
      SAXIHP1ARSIZE => s_fwd(3).ar.size,
      SAXIHP1ARVALID => s_fwd(3).ar.valid,
      SAXIHP1AWADDR => s_fwd(3).aw.addr,
      SAXIHP1AWBURST => s_fwd(3).aw.burst,
      SAXIHP1AWCACHE => s_fwd(3).aw.cache,
      SAXIHP1AWID => s_fwd(3).aw.id(5 downto 0),
      SAXIHP1AWLEN => s_fwd(3).aw.len,
      SAXIHP1AWLOCK => s_fwd(3).aw.lock,
      SAXIHP1AWPROT => s_fwd(3).aw.prot,
      SAXIHP1AWQOS => s_fwd(3).aw.qos,
      SAXIHP1AWSIZE => s_fwd(3).aw.size,
      SAXIHP1AWVALID => s_fwd(3).aw.valid,
      SAXIHP1BREADY => s_fwd(3).bready,
      SAXIHP1RDISSUECAP1EN => hp_rd_issue_cap1(1),
      SAXIHP1RREADY => s_fwd(3).rready,
      SAXIHP1WDATA => s_fwd(3).wdata,
      SAXIHP1WID => s_fwd(3).wid(5 downto 0),
      SAXIHP1WLAST => s_fwd(3).wlast,
      SAXIHP1WRISSUECAP1EN => hp_wr_issue_cap1(1),
      SAXIHP1WSTRB => s_fwd(3).wstrb,
      SAXIHP1WVALID => s_fwd(3).wvalid,
      SAXIHP2ACLK => s_aclk(4),
      SAXIHP2ARADDR => s_fwd(4).ar.addr,
      SAXIHP2ARBURST => s_fwd(4).ar.burst,
      SAXIHP2ARCACHE => s_fwd(4).ar.cache,
      SAXIHP2ARID => s_fwd(4).ar.id(5 downto 0),
      SAXIHP2ARLEN => s_fwd(4).ar.len,
      SAXIHP2ARLOCK => s_fwd(4).ar.lock,
      SAXIHP2ARPROT => s_fwd(4).ar.prot,
      SAXIHP2ARQOS => s_fwd(4).ar.qos,
      SAXIHP2ARSIZE => s_fwd(4).ar.size,
      SAXIHP2ARVALID => s_fwd(4).ar.valid,
      SAXIHP2AWADDR => s_fwd(4).aw.addr,
      SAXIHP2AWBURST => s_fwd(4).aw.burst,
      SAXIHP2AWCACHE => s_fwd(4).aw.cache,
      SAXIHP2AWID => s_fwd(4).aw.id(5 downto 0),
      SAXIHP2AWLEN => s_fwd(4).aw.len,
      SAXIHP2AWLOCK => s_fwd(4).aw.lock,
      SAXIHP2AWPROT => s_fwd(4).aw.prot,
      SAXIHP2AWQOS => s_fwd(4).aw.qos,
      SAXIHP2AWSIZE => s_fwd(4).aw.size,
      SAXIHP2AWVALID => s_fwd(4).aw.valid,
      SAXIHP2BREADY => s_fwd(4).bready,
      SAXIHP2RDISSUECAP1EN => hp_rd_issue_cap1(2),
      SAXIHP2RREADY => s_fwd(4).rready,
      SAXIHP2WDATA => s_fwd(4).wdata,
      SAXIHP2WID => s_fwd(4).wid(5 downto 0),
      SAXIHP2WLAST => s_fwd(4).wlast,
      SAXIHP2WRISSUECAP1EN => hp_wr_issue_cap1(2),
      SAXIHP2WSTRB => s_fwd(4).wstrb,
      SAXIHP2WVALID => s_fwd(4).wvalid,
      SAXIHP3ACLK => s_aclk(5),
      SAXIHP3ARADDR => s_fwd(5).ar.addr,
      SAXIHP3ARBURST => s_fwd(5).ar.burst,
      SAXIHP3ARCACHE => s_fwd(5).ar.cache,
      SAXIHP3ARID => s_fwd(5).ar.id(5 downto 0),
      SAXIHP3ARLEN => s_fwd(5).ar.len,
      SAXIHP3ARLOCK => s_fwd(5).ar.lock,
      SAXIHP3ARPROT => s_fwd(5).ar.prot,
      SAXIHP3ARQOS => s_fwd(5).ar.qos,
      SAXIHP3ARSIZE => s_fwd(5).ar.size,
      SAXIHP3ARVALID => s_fwd(5).ar.valid,
      SAXIHP3AWADDR => s_fwd(5).aw.addr,
      SAXIHP3AWBURST => s_fwd(5).aw.burst,
      SAXIHP3AWCACHE => s_fwd(5).aw.cache,
      SAXIHP3AWID => s_fwd(5).aw.id(5 downto 0),
      SAXIHP3AWLEN => s_fwd(5).aw.len,
      SAXIHP3AWLOCK => s_fwd(5).aw.lock,
      SAXIHP3AWPROT => s_fwd(5).aw.prot,
      SAXIHP3AWQOS => s_fwd(5).aw.qos,
      SAXIHP3AWSIZE => s_fwd(5).aw.size,
      SAXIHP3AWVALID => s_fwd(5).aw.valid,
      SAXIHP3BREADY => s_fwd(5).bready,
      SAXIHP3RDISSUECAP1EN => hp_rd_issue_cap1(3),
      SAXIHP3RREADY => s_fwd(5).rready,
      SAXIHP3WDATA => s_fwd(5).wdata,
      SAXIHP3WID => s_fwd(5).wid(5 downto 0),
      SAXIHP3WLAST => s_fwd(5).wlast,
      SAXIHP3WRISSUECAP1EN => hp_wr_issue_cap1(3),
      SAXIHP3WSTRB => s_fwd(5).wstrb,
      SAXIHP3WVALID => s_fwd(5).wvalid
      );

  clocks: for i in 0 to 3
  generate
    fclk_o(i) <= fclk_s(i);
    fclk_reset_n_o(i) <= fclk_reset_n_s(i);
  end generate;

  irq_f2p: for i in 0 to 15
  generate
    irq_f2p_s(i) <= irq_f2p_i(i);
  end generate;
  -- Core0/1 nIRQ/nFIQ, tied as Xilinx IP does.
  irq_f2p_s(19 downto 16) <= (others => '0');

  dmac_irq: for i in 0 to 7
  generate
    dmac_irq_o(i) <= irq_p2f_s(20 + i);
  end generate;
  dmac_irq_abort_o <= irq_p2f_s(28);

  dmac: for i in 0 to 3
  generate
    dma_ps_i(i).drvalid <= dmac_periph_i(i).drvalid;
    dma_ps_i(i).drtype <= std_logic_vector(dmac_periph_i(i).drtype);
    dma_ps_i(i).drlast <= dmac_periph_i(i).drlast;
    dma_ps_i(i).daready <= dmac_periph_i(i).daready;
    dmac_periph_o(i).drready <= dma_ps_o(i).drready;
    dmac_periph_o(i).davalid <= dma_ps_o(i).davalid;
    dmac_periph_o(i).datype <= std_ulogic_vector(dma_ps_o(i).datype);
  end generate;

  m_aclk(0) <= m_axi_gp0_clock_i;
  m_aclk(1) <= m_axi_gp1_clock_i;
  m_axi_gp0_reset_n_o <= m_aresetn(0);
  m_axi_gp1_reset_n_o <= m_aresetn(1);
  m_axi_gp0_o <= m_o(0);
  m_axi_gp1_o <= m_o(1);
  m_i(0) <= m_axi_gp0_i;
  m_i(1) <= m_axi_gp1_i;

  s_aclk <= (s_axi_gp0_clock_i, s_axi_gp1_clock_i,
             s_axi_hp0_clock_i, s_axi_hp1_clock_i,
             s_axi_hp2_clock_i, s_axi_hp3_clock_i,
             s_axi_acp_clock_i);
  s_axi_gp0_reset_n_o <= s_aresetn(0);
  s_axi_gp1_reset_n_o <= s_aresetn(1);
  s_axi_hp0_reset_n_o <= s_aresetn(2);
  s_axi_hp1_reset_n_o <= s_aresetn(3);
  s_axi_hp2_reset_n_o <= s_aresetn(4);
  s_axi_hp3_reset_n_o <= s_aresetn(5);
  s_axi_acp_reset_n_o <= s_aresetn(6);
  s_axi_gp0_o <= s_o(0);
  s_axi_gp1_o <= s_o(1);
  s_axi_hp0_o <= s_o(2);
  s_axi_hp1_o <= s_o(3);
  s_axi_hp2_o <= s_o(4);
  s_axi_hp3_o <= s_o(5);
  s_axi_acp_o <= s_o(6);
  s_i <= (s_axi_gp0_i, s_axi_gp1_i,
          s_axi_hp0_i, s_axi_hp1_i,
          s_axi_hp2_i, s_axi_hp3_i,
          s_axi_acp_i);

  hp_rd_issue_cap1 <= (s_axi_hp0_read_issue_cap1_i, s_axi_hp1_read_issue_cap1_i,
                       s_axi_hp2_read_issue_cap1_i, s_axi_hp3_read_issue_cap1_i);
  hp_wr_issue_cap1 <= (s_axi_hp0_write_issue_cap1_i, s_axi_hp1_write_issue_cap1_i,
                       s_axi_hp2_write_issue_cap1_i, s_axi_hp3_write_issue_cap1_i);
  s_axi_hp0_level_o <= (read_data => unsigned(hp_level(0).rcount),
                          write_data => unsigned(hp_level(0).wcount),
                          read_command => unsigned(hp_level(0).racount),
                          write_command => unsigned(hp_level(0).wacount));
  s_axi_hp1_level_o <= (read_data => unsigned(hp_level(1).rcount),
                          write_data => unsigned(hp_level(1).wcount),
                          read_command => unsigned(hp_level(1).racount),
                          write_command => unsigned(hp_level(1).wacount));
  s_axi_hp2_level_o <= (read_data => unsigned(hp_level(2).rcount),
                          write_data => unsigned(hp_level(2).wcount),
                          read_command => unsigned(hp_level(2).racount),
                          write_command => unsigned(hp_level(2).wacount));
  s_axi_hp3_level_o <= (read_data => unsigned(hp_level(3).rcount),
                          write_data => unsigned(hp_level(3).wcount),
                          read_command => unsigned(hp_level(3).racount),
                          write_command => unsigned(hp_level(3).wacount));

  m_gp: for i in 0 to 1
  generate
  begin
    m_o(i) <= to_master(m_gp_config_c(i), m_fwd(i));
    m_bwd(i) <= to_ps_bwd(m_gp_config_c(i), m_i(i));
  end generate;

  s_port: for i in s_config_c'range
  generate
    signal aw_valid_s, aw_ready_s, w_valid_s, w_ready_s: std_ulogic;
    signal aw_id_s, w_id_s: std_ulogic_vector(s_native_config_c(i).id_width-1 downto 0);
    signal s_fwd_s: ps_fwd_t;
  begin
    s_fwd_s <= to_ps_fwd(s_config_c(i), s_i(i));
    aw_id_s <= std_ulogic_vector(s_fwd_s.aw.id(aw_id_s'range));

    s_wid: nsl_xilinx.ps7.ps7_axi3_wid_tracker
      generic map(
        id_width_c => s_native_config_c(i).id_width,
        depth_c => s_write_acceptance_c(i)
        )
      port map(
        clock_i => s_aclk(i),
        reset_n_i => s_aresetn(i),

        aw_valid_i => s_fwd_s.aw.valid,
        aw_id_i => aw_id_s,
        aw_valid_o => aw_valid_s,
        aw_ready_i => s_bwd(i).awready,
        aw_ready_o => aw_ready_s,

        w_valid_i => s_fwd_s.wvalid,
        w_last_i => s_fwd_s.wlast,
        w_valid_o => w_valid_s,
        w_ready_i => s_bwd(i).wready,
        w_ready_o => w_ready_s,
        w_id_o => w_id_s
        );

    s_fwd_map: process(s_fwd_s, aw_valid_s, w_valid_s, w_id_s) is
      variable f: ps_fwd_t;
    begin
      f := s_fwd_s;
      f.aw.valid := aw_valid_s;
      f.wvalid := w_valid_s;
      f.wid(w_id_s'range) := std_logic_vector(w_id_s);
      s_fwd(i) <= f;
    end process;

    s_bwd_map: process(s_bwd(i), aw_ready_s, w_ready_s) is
      variable s: slave_t;
    begin
      s := to_slave(s_config_c(i), s_bwd(i));
      s.aw.ready := aw_ready_s;
      s.w.ready := w_ready_s;
      s_o(i) <= s;
    end process;
  end generate;


  assert spi0_decoded_cs_c or spi0_slave_count_c <= 3
    report "SPI0 drives at most 3 slaves without decoded chip selects"
    severity failure;

  spi0_slaves: for i in 0 to spi0_slave_count_c-1
  generate
    spi0_selected_s(i) <= spi_selected(spi0_sson_s, spi0_ssntn_s, spi0_decoded_cs_c, i);
    spi0_o(i).sck <= spi0_sclko_s;
    spi0_o(i).mosi.v <= spi0_mo_s;
    spi0_o(i).mosi.en <= spi0_motn_s and spi0_selected_s(i);
    spi0_o(i).cs_n.drain_n <= not spi0_selected_s(i);
  end generate;

  spi0_mi_s <= spi_miso(spi0_selected_s, spi0_i);

  gem0_gmii_tx_o.data <= std_ulogic_vector(gem0_gmii_txd_s);
  gem0_gmii_rxd_s <= std_logic_vector(gem0_gmii_rx_i.data);

  uart0_o.rts <= not uart0_rtsn_s;
  uart0_o.dtr <= not uart0_dtrn_s;
  uart0_o.dcd <= '0';
  uart0_o.ri <= '0';
  uart0_ctsn_s <= not uart0_i.rts;
  uart0_dsrn_s <= not uart0_i.dtr;
  uart0_dcdn_s <= not uart0_i.dcd;
  uart0_rin_s <= not uart0_i.ri;

  i2c0_o.scl.drain_n <= not (i2c0_scl_tn_s and not i2c0_scl_o_s);
  i2c0_o.sda.drain_n <= not (i2c0_sda_tn_s and not i2c0_sda_o_s);

  assert spi1_decoded_cs_c or spi1_slave_count_c <= 3
    report "SPI1 drives at most 3 slaves without decoded chip selects"
    severity failure;

  spi1_slaves: for i in 0 to spi1_slave_count_c-1
  generate
    spi1_selected_s(i) <= spi_selected(spi1_sson_s, spi1_ssntn_s, spi1_decoded_cs_c, i);
    spi1_o(i).sck <= spi1_sclko_s;
    spi1_o(i).mosi.v <= spi1_mo_s;
    spi1_o(i).mosi.en <= spi1_motn_s and spi1_selected_s(i);
    spi1_o(i).cs_n.drain_n <= not spi1_selected_s(i);
  end generate;

  spi1_mi_s <= spi_miso(spi1_selected_s, spi1_i);

  gem1_gmii_tx_o.data <= std_ulogic_vector(gem1_gmii_txd_s);
  gem1_gmii_rxd_s <= std_logic_vector(gem1_gmii_rx_i.data);

  uart1_o.rts <= not uart1_rtsn_s;
  uart1_o.dtr <= not uart1_dtrn_s;
  uart1_o.dcd <= '0';
  uart1_o.ri <= '0';
  uart1_ctsn_s <= not uart1_i.rts;
  uart1_dsrn_s <= not uart1_i.dtr;
  uart1_dcdn_s <= not uart1_i.dcd;
  uart1_rin_s <= not uart1_i.ri;

  i2c1_o.scl.drain_n <= not (i2c1_scl_tn_s and not i2c1_scl_o_s);
  i2c1_o.sda.drain_n <= not (i2c1_sda_tn_s and not i2c1_sda_o_s);

  gpio: for i in 0 to 63
  generate
    gpio_o(i).v <= gpio_o_s(i);
    gpio_o(i).en <= gpio_tn_s(i);
    gpio_i_s(i) <= gpio_i(i);
  end generate;

  registers: if report_registers_c
  generate
    assert false
      report register_note(slcr_lvl_shftr_en_c, 16#F#, 16#F#,
                           "LVL_SHFTR_EN, PS-PL level shifters enabled")
      severity note;

    hp: for n in 0 to 3
    generate
      constant narrow_c : natural range 0 to 1
        := to_natural(s_config_c(2 + n).data_bus_width_l2 = 2);
      constant comment_c : string
        := "32BitEn, S_AXI_HP" & integer'image(n) & " "
        & integer'image(8 * 2 ** s_config_c(2 + n).data_bus_width_l2) & "-bit";
    begin
      assert false
        report register_note(afi_base_c + n * afi_stride_c + afi_rdchan_ctrl_c,
                             1, narrow_c,
                             "AFI" & integer'image(n) & "_RDCHAN_CTRL." & comment_c)
        severity note;
      assert false
        report register_note(afi_base_c + n * afi_stride_c + afi_wrchan_ctrl_c,
                             1, narrow_c,
                             "AFI" & integer'image(n) & "_WRCHAN_CTRL." & comment_c)
        severity note;
    end generate;

    fclk: for n in 0 to 3
    generate
      used: if fclk_frequency_c(n) /= 0
      generate
        assert false
          report "nsl_xilinx.ps7: fclk " & integer'image(n)
          & " frequency " & integer'image(fclk_frequency_c(n)) & " Hz"
          severity note;
      end generate;
    end generate;
  end generate;

end architecture;
