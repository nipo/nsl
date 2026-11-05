library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_xilinx, nsl_data, nsl_spi, nsl_mii, nsl_smi, nsl_uart, nsl_i2c, nsl_io;
use nsl_amba.axi4_mm.all;
use nsl_xilinx.ps8.all;
use nsl_data.endian.all;

entity ps8_wrapper is
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
end entity;

-- The PS8 primitive has no simulation model, this architecture is only
-- meant for synthesis.  Every input of the primitive this wrapper does
-- not expose is tied to the value Xilinx zynq_ultra_ps_e IP gives it
-- for a disabled interface, every output it does not expose is left
-- open.  SPI slave select inputs are tied high: SPI controllers are
-- only usable as masters, this prevents mode faults.  PS dedicated
-- pads (PS-GTR) are left unconnected.
architecture zynqmp of ps8_wrapper is

  attribute BOX_TYPE : string;

  component PS8 is
    port(
      ADMA2PLCACK : out std_logic_vector(7 downto 0);
      ADMA2PLTVLD : out std_logic_vector(7 downto 0);
      DPAUDIOREFCLK : out std_ulogic;
      DPAUXDATAOEN : out std_ulogic;
      DPAUXDATAOUT : out std_ulogic;
      DPLIVEVIDEODEOUT : out std_ulogic;
      DPMAXISMIXEDAUDIOTDATA : out std_logic_vector(31 downto 0);
      DPMAXISMIXEDAUDIOTID : out std_ulogic;
      DPMAXISMIXEDAUDIOTVALID : out std_ulogic;
      DPSAXISAUDIOTREADY : out std_ulogic;
      DPVIDEOOUTHSYNC : out std_ulogic;
      DPVIDEOOUTPIXEL1 : out std_logic_vector(35 downto 0);
      DPVIDEOOUTVSYNC : out std_ulogic;
      DPVIDEOREFCLK : out std_ulogic;
      EMIOCAN0PHYTX : out std_ulogic;
      EMIOCAN1PHYTX : out std_ulogic;
      EMIOENET0DMABUSWIDTH : out std_logic_vector(1 downto 0);
      EMIOENET0DMATXENDTOG : out std_ulogic;
      EMIOENET0GEMTSUTIMERCNT : out std_logic_vector(93 downto 0);
      EMIOENET0GMIITXD : out std_logic_vector(7 downto 0);
      EMIOENET0GMIITXEN : out std_ulogic;
      EMIOENET0GMIITXER : out std_ulogic;
      EMIOENET0MDIOMDC : out std_ulogic;
      EMIOENET0MDIOO : out std_ulogic;
      EMIOENET0MDIOTN : out std_ulogic;
      EMIOENET0RXWDATA : out std_logic_vector(7 downto 0);
      EMIOENET0RXWEOP : out std_ulogic;
      EMIOENET0RXWERR : out std_ulogic;
      EMIOENET0RXWFLUSH : out std_ulogic;
      EMIOENET0RXWSOP : out std_ulogic;
      EMIOENET0RXWSTATUS : out std_logic_vector(44 downto 0);
      EMIOENET0RXWWR : out std_ulogic;
      EMIOENET0SPEEDMODE : out std_logic_vector(2 downto 0);
      EMIOENET0TXRRD : out std_ulogic;
      EMIOENET0TXRSTATUS : out std_logic_vector(3 downto 0);
      EMIOENET1DMABUSWIDTH : out std_logic_vector(1 downto 0);
      EMIOENET1DMATXENDTOG : out std_ulogic;
      EMIOENET1GMIITXD : out std_logic_vector(7 downto 0);
      EMIOENET1GMIITXEN : out std_ulogic;
      EMIOENET1GMIITXER : out std_ulogic;
      EMIOENET1MDIOMDC : out std_ulogic;
      EMIOENET1MDIOO : out std_ulogic;
      EMIOENET1MDIOTN : out std_ulogic;
      EMIOENET1RXWDATA : out std_logic_vector(7 downto 0);
      EMIOENET1RXWEOP : out std_ulogic;
      EMIOENET1RXWERR : out std_ulogic;
      EMIOENET1RXWFLUSH : out std_ulogic;
      EMIOENET1RXWSOP : out std_ulogic;
      EMIOENET1RXWSTATUS : out std_logic_vector(44 downto 0);
      EMIOENET1RXWWR : out std_ulogic;
      EMIOENET1SPEEDMODE : out std_logic_vector(2 downto 0);
      EMIOENET1TXRRD : out std_ulogic;
      EMIOENET1TXRSTATUS : out std_logic_vector(3 downto 0);
      EMIOENET2DMABUSWIDTH : out std_logic_vector(1 downto 0);
      EMIOENET2DMATXENDTOG : out std_ulogic;
      EMIOENET2GMIITXD : out std_logic_vector(7 downto 0);
      EMIOENET2GMIITXEN : out std_ulogic;
      EMIOENET2GMIITXER : out std_ulogic;
      EMIOENET2MDIOMDC : out std_ulogic;
      EMIOENET2MDIOO : out std_ulogic;
      EMIOENET2MDIOTN : out std_ulogic;
      EMIOENET2RXWDATA : out std_logic_vector(7 downto 0);
      EMIOENET2RXWEOP : out std_ulogic;
      EMIOENET2RXWERR : out std_ulogic;
      EMIOENET2RXWFLUSH : out std_ulogic;
      EMIOENET2RXWSOP : out std_ulogic;
      EMIOENET2RXWSTATUS : out std_logic_vector(44 downto 0);
      EMIOENET2RXWWR : out std_ulogic;
      EMIOENET2SPEEDMODE : out std_logic_vector(2 downto 0);
      EMIOENET2TXRRD : out std_ulogic;
      EMIOENET2TXRSTATUS : out std_logic_vector(3 downto 0);
      EMIOENET3DMABUSWIDTH : out std_logic_vector(1 downto 0);
      EMIOENET3DMATXENDTOG : out std_ulogic;
      EMIOENET3GMIITXD : out std_logic_vector(7 downto 0);
      EMIOENET3GMIITXEN : out std_ulogic;
      EMIOENET3GMIITXER : out std_ulogic;
      EMIOENET3MDIOMDC : out std_ulogic;
      EMIOENET3MDIOO : out std_ulogic;
      EMIOENET3MDIOTN : out std_ulogic;
      EMIOENET3RXWDATA : out std_logic_vector(7 downto 0);
      EMIOENET3RXWEOP : out std_ulogic;
      EMIOENET3RXWERR : out std_ulogic;
      EMIOENET3RXWFLUSH : out std_ulogic;
      EMIOENET3RXWSOP : out std_ulogic;
      EMIOENET3RXWSTATUS : out std_logic_vector(44 downto 0);
      EMIOENET3RXWWR : out std_ulogic;
      EMIOENET3SPEEDMODE : out std_logic_vector(2 downto 0);
      EMIOENET3TXRRD : out std_ulogic;
      EMIOENET3TXRSTATUS : out std_logic_vector(3 downto 0);
      EMIOGEM0DELAYREQRX : out std_ulogic;
      EMIOGEM0DELAYREQTX : out std_ulogic;
      EMIOGEM0PDELAYREQRX : out std_ulogic;
      EMIOGEM0PDELAYREQTX : out std_ulogic;
      EMIOGEM0PDELAYRESPRX : out std_ulogic;
      EMIOGEM0PDELAYRESPTX : out std_ulogic;
      EMIOGEM0RXSOF : out std_ulogic;
      EMIOGEM0SYNCFRAMERX : out std_ulogic;
      EMIOGEM0SYNCFRAMETX : out std_ulogic;
      EMIOGEM0TSUTIMERCMPVAL : out std_ulogic;
      EMIOGEM0TXRFIXEDLAT : out std_ulogic;
      EMIOGEM0TXSOF : out std_ulogic;
      EMIOGEM1DELAYREQRX : out std_ulogic;
      EMIOGEM1DELAYREQTX : out std_ulogic;
      EMIOGEM1PDELAYREQRX : out std_ulogic;
      EMIOGEM1PDELAYREQTX : out std_ulogic;
      EMIOGEM1PDELAYRESPRX : out std_ulogic;
      EMIOGEM1PDELAYRESPTX : out std_ulogic;
      EMIOGEM1RXSOF : out std_ulogic;
      EMIOGEM1SYNCFRAMERX : out std_ulogic;
      EMIOGEM1SYNCFRAMETX : out std_ulogic;
      EMIOGEM1TSUTIMERCMPVAL : out std_ulogic;
      EMIOGEM1TXRFIXEDLAT : out std_ulogic;
      EMIOGEM1TXSOF : out std_ulogic;
      EMIOGEM2DELAYREQRX : out std_ulogic;
      EMIOGEM2DELAYREQTX : out std_ulogic;
      EMIOGEM2PDELAYREQRX : out std_ulogic;
      EMIOGEM2PDELAYREQTX : out std_ulogic;
      EMIOGEM2PDELAYRESPRX : out std_ulogic;
      EMIOGEM2PDELAYRESPTX : out std_ulogic;
      EMIOGEM2RXSOF : out std_ulogic;
      EMIOGEM2SYNCFRAMERX : out std_ulogic;
      EMIOGEM2SYNCFRAMETX : out std_ulogic;
      EMIOGEM2TSUTIMERCMPVAL : out std_ulogic;
      EMIOGEM2TXRFIXEDLAT : out std_ulogic;
      EMIOGEM2TXSOF : out std_ulogic;
      EMIOGEM3DELAYREQRX : out std_ulogic;
      EMIOGEM3DELAYREQTX : out std_ulogic;
      EMIOGEM3PDELAYREQRX : out std_ulogic;
      EMIOGEM3PDELAYREQTX : out std_ulogic;
      EMIOGEM3PDELAYRESPRX : out std_ulogic;
      EMIOGEM3PDELAYRESPTX : out std_ulogic;
      EMIOGEM3RXSOF : out std_ulogic;
      EMIOGEM3SYNCFRAMERX : out std_ulogic;
      EMIOGEM3SYNCFRAMETX : out std_ulogic;
      EMIOGEM3TSUTIMERCMPVAL : out std_ulogic;
      EMIOGEM3TXRFIXEDLAT : out std_ulogic;
      EMIOGEM3TXSOF : out std_ulogic;
      EMIOGPIOO : out std_logic_vector(95 downto 0);
      EMIOGPIOTN : out std_logic_vector(95 downto 0);
      EMIOI2C0SCLO : out std_ulogic;
      EMIOI2C0SCLTN : out std_ulogic;
      EMIOI2C0SDAO : out std_ulogic;
      EMIOI2C0SDATN : out std_ulogic;
      EMIOI2C1SCLO : out std_ulogic;
      EMIOI2C1SCLTN : out std_ulogic;
      EMIOI2C1SDAO : out std_ulogic;
      EMIOI2C1SDATN : out std_ulogic;
      EMIOSDIO0BUSPOWER : out std_ulogic;
      EMIOSDIO0BUSVOLT : out std_logic_vector(2 downto 0);
      EMIOSDIO0CLKOUT : out std_ulogic;
      EMIOSDIO0CMDENA : out std_ulogic;
      EMIOSDIO0CMDOUT : out std_ulogic;
      EMIOSDIO0DATAENA : out std_logic_vector(7 downto 0);
      EMIOSDIO0DATAOUT : out std_logic_vector(7 downto 0);
      EMIOSDIO0LEDCONTROL : out std_ulogic;
      EMIOSDIO1BUSPOWER : out std_ulogic;
      EMIOSDIO1BUSVOLT : out std_logic_vector(2 downto 0);
      EMIOSDIO1CLKOUT : out std_ulogic;
      EMIOSDIO1CMDENA : out std_ulogic;
      EMIOSDIO1CMDOUT : out std_ulogic;
      EMIOSDIO1DATAENA : out std_logic_vector(7 downto 0);
      EMIOSDIO1DATAOUT : out std_logic_vector(7 downto 0);
      EMIOSDIO1LEDCONTROL : out std_ulogic;
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
      EMIOTTC0WAVEO : out std_logic_vector(2 downto 0);
      EMIOTTC1WAVEO : out std_logic_vector(2 downto 0);
      EMIOTTC2WAVEO : out std_logic_vector(2 downto 0);
      EMIOTTC3WAVEO : out std_logic_vector(2 downto 0);
      EMIOU2DSPORTVBUSCTRLUSB30 : out std_ulogic;
      EMIOU2DSPORTVBUSCTRLUSB31 : out std_ulogic;
      EMIOU3DSPORTVBUSCTRLUSB30 : out std_ulogic;
      EMIOU3DSPORTVBUSCTRLUSB31 : out std_ulogic;
      EMIOUART0DTRN : out std_ulogic;
      EMIOUART0RTSN : out std_ulogic;
      EMIOUART0TX : out std_ulogic;
      EMIOUART1DTRN : out std_ulogic;
      EMIOUART1RTSN : out std_ulogic;
      EMIOUART1TX : out std_ulogic;
      EMIOWDT0RSTO : out std_ulogic;
      EMIOWDT1RSTO : out std_ulogic;
      FMIOGEM0FIFORXCLKTOPLBUFG : out std_ulogic;
      FMIOGEM0FIFOTXCLKTOPLBUFG : out std_ulogic;
      FMIOGEM1FIFORXCLKTOPLBUFG : out std_ulogic;
      FMIOGEM1FIFOTXCLKTOPLBUFG : out std_ulogic;
      FMIOGEM2FIFORXCLKTOPLBUFG : out std_ulogic;
      FMIOGEM2FIFOTXCLKTOPLBUFG : out std_ulogic;
      FMIOGEM3FIFORXCLKTOPLBUFG : out std_ulogic;
      FMIOGEM3FIFOTXCLKTOPLBUFG : out std_ulogic;
      FMIOGEMTSUCLKTOPLBUFG : out std_ulogic;
      FTMGPO : out std_logic_vector(31 downto 0);
      GDMA2PLCACK : out std_logic_vector(7 downto 0);
      GDMA2PLTVLD : out std_logic_vector(7 downto 0);
      MAXIGP0ARADDR : out std_logic_vector(39 downto 0);
      MAXIGP0ARBURST : out std_logic_vector(1 downto 0);
      MAXIGP0ARCACHE : out std_logic_vector(3 downto 0);
      MAXIGP0ARID : out std_logic_vector(15 downto 0);
      MAXIGP0ARLEN : out std_logic_vector(7 downto 0);
      MAXIGP0ARLOCK : out std_ulogic;
      MAXIGP0ARPROT : out std_logic_vector(2 downto 0);
      MAXIGP0ARQOS : out std_logic_vector(3 downto 0);
      MAXIGP0ARSIZE : out std_logic_vector(2 downto 0);
      MAXIGP0ARUSER : out std_logic_vector(15 downto 0);
      MAXIGP0ARVALID : out std_ulogic;
      MAXIGP0AWADDR : out std_logic_vector(39 downto 0);
      MAXIGP0AWBURST : out std_logic_vector(1 downto 0);
      MAXIGP0AWCACHE : out std_logic_vector(3 downto 0);
      MAXIGP0AWID : out std_logic_vector(15 downto 0);
      MAXIGP0AWLEN : out std_logic_vector(7 downto 0);
      MAXIGP0AWLOCK : out std_ulogic;
      MAXIGP0AWPROT : out std_logic_vector(2 downto 0);
      MAXIGP0AWQOS : out std_logic_vector(3 downto 0);
      MAXIGP0AWSIZE : out std_logic_vector(2 downto 0);
      MAXIGP0AWUSER : out std_logic_vector(15 downto 0);
      MAXIGP0AWVALID : out std_ulogic;
      MAXIGP0BREADY : out std_ulogic;
      MAXIGP0RREADY : out std_ulogic;
      MAXIGP0WDATA : out std_logic_vector(127 downto 0);
      MAXIGP0WLAST : out std_ulogic;
      MAXIGP0WSTRB : out std_logic_vector(15 downto 0);
      MAXIGP0WVALID : out std_ulogic;
      MAXIGP1ARADDR : out std_logic_vector(39 downto 0);
      MAXIGP1ARBURST : out std_logic_vector(1 downto 0);
      MAXIGP1ARCACHE : out std_logic_vector(3 downto 0);
      MAXIGP1ARID : out std_logic_vector(15 downto 0);
      MAXIGP1ARLEN : out std_logic_vector(7 downto 0);
      MAXIGP1ARLOCK : out std_ulogic;
      MAXIGP1ARPROT : out std_logic_vector(2 downto 0);
      MAXIGP1ARQOS : out std_logic_vector(3 downto 0);
      MAXIGP1ARSIZE : out std_logic_vector(2 downto 0);
      MAXIGP1ARUSER : out std_logic_vector(15 downto 0);
      MAXIGP1ARVALID : out std_ulogic;
      MAXIGP1AWADDR : out std_logic_vector(39 downto 0);
      MAXIGP1AWBURST : out std_logic_vector(1 downto 0);
      MAXIGP1AWCACHE : out std_logic_vector(3 downto 0);
      MAXIGP1AWID : out std_logic_vector(15 downto 0);
      MAXIGP1AWLEN : out std_logic_vector(7 downto 0);
      MAXIGP1AWLOCK : out std_ulogic;
      MAXIGP1AWPROT : out std_logic_vector(2 downto 0);
      MAXIGP1AWQOS : out std_logic_vector(3 downto 0);
      MAXIGP1AWSIZE : out std_logic_vector(2 downto 0);
      MAXIGP1AWUSER : out std_logic_vector(15 downto 0);
      MAXIGP1AWVALID : out std_ulogic;
      MAXIGP1BREADY : out std_ulogic;
      MAXIGP1RREADY : out std_ulogic;
      MAXIGP1WDATA : out std_logic_vector(127 downto 0);
      MAXIGP1WLAST : out std_ulogic;
      MAXIGP1WSTRB : out std_logic_vector(15 downto 0);
      MAXIGP1WVALID : out std_ulogic;
      MAXIGP2ARADDR : out std_logic_vector(39 downto 0);
      MAXIGP2ARBURST : out std_logic_vector(1 downto 0);
      MAXIGP2ARCACHE : out std_logic_vector(3 downto 0);
      MAXIGP2ARID : out std_logic_vector(15 downto 0);
      MAXIGP2ARLEN : out std_logic_vector(7 downto 0);
      MAXIGP2ARLOCK : out std_ulogic;
      MAXIGP2ARPROT : out std_logic_vector(2 downto 0);
      MAXIGP2ARQOS : out std_logic_vector(3 downto 0);
      MAXIGP2ARSIZE : out std_logic_vector(2 downto 0);
      MAXIGP2ARUSER : out std_logic_vector(15 downto 0);
      MAXIGP2ARVALID : out std_ulogic;
      MAXIGP2AWADDR : out std_logic_vector(39 downto 0);
      MAXIGP2AWBURST : out std_logic_vector(1 downto 0);
      MAXIGP2AWCACHE : out std_logic_vector(3 downto 0);
      MAXIGP2AWID : out std_logic_vector(15 downto 0);
      MAXIGP2AWLEN : out std_logic_vector(7 downto 0);
      MAXIGP2AWLOCK : out std_ulogic;
      MAXIGP2AWPROT : out std_logic_vector(2 downto 0);
      MAXIGP2AWQOS : out std_logic_vector(3 downto 0);
      MAXIGP2AWSIZE : out std_logic_vector(2 downto 0);
      MAXIGP2AWUSER : out std_logic_vector(15 downto 0);
      MAXIGP2AWVALID : out std_ulogic;
      MAXIGP2BREADY : out std_ulogic;
      MAXIGP2RREADY : out std_ulogic;
      MAXIGP2WDATA : out std_logic_vector(127 downto 0);
      MAXIGP2WLAST : out std_ulogic;
      MAXIGP2WSTRB : out std_logic_vector(15 downto 0);
      MAXIGP2WVALID : out std_ulogic;
      OSCRTCCLK : out std_ulogic;
      PLCLK : out std_logic_vector(3 downto 0);
      PMUAIBAFIFMFPDREQ : out std_ulogic;
      PMUAIBAFIFMLPDREQ : out std_ulogic;
      PMUERRORTOPL : out std_logic_vector(46 downto 0);
      PMUPLGPO : out std_logic_vector(31 downto 0);
      PSPLEVENTO : out std_ulogic;
      PSPLIRQFPD : out std_logic_vector(63 downto 0);
      PSPLIRQLPD : out std_logic_vector(99 downto 0);
      PSPLSTANDBYWFE : out std_logic_vector(3 downto 0);
      PSPLSTANDBYWFI : out std_logic_vector(3 downto 0);
      PSPLTRACECTL : out std_ulogic;
      PSPLTRACEDATA : out std_logic_vector(31 downto 0);
      PSPLTRIGACK : out std_logic_vector(3 downto 0);
      PSPLTRIGGER : out std_logic_vector(3 downto 0);
      RPUEVENTO0 : out std_ulogic;
      RPUEVENTO1 : out std_ulogic;
      SACEFPDACADDR : out std_logic_vector(43 downto 0);
      SACEFPDACPROT : out std_logic_vector(2 downto 0);
      SACEFPDACSNOOP : out std_logic_vector(3 downto 0);
      SACEFPDACVALID : out std_ulogic;
      SACEFPDARREADY : out std_ulogic;
      SACEFPDAWREADY : out std_ulogic;
      SACEFPDBID : out std_logic_vector(5 downto 0);
      SACEFPDBRESP : out std_logic_vector(1 downto 0);
      SACEFPDBUSER : out std_ulogic;
      SACEFPDBVALID : out std_ulogic;
      SACEFPDCDREADY : out std_ulogic;
      SACEFPDCRREADY : out std_ulogic;
      SACEFPDRDATA : out std_logic_vector(127 downto 0);
      SACEFPDRID : out std_logic_vector(5 downto 0);
      SACEFPDRLAST : out std_ulogic;
      SACEFPDRRESP : out std_logic_vector(3 downto 0);
      SACEFPDRUSER : out std_ulogic;
      SACEFPDRVALID : out std_ulogic;
      SACEFPDWREADY : out std_ulogic;
      SAXIACPARREADY : out std_ulogic;
      SAXIACPAWREADY : out std_ulogic;
      SAXIACPBID : out std_logic_vector(4 downto 0);
      SAXIACPBRESP : out std_logic_vector(1 downto 0);
      SAXIACPBVALID : out std_ulogic;
      SAXIACPRDATA : out std_logic_vector(127 downto 0);
      SAXIACPRID : out std_logic_vector(4 downto 0);
      SAXIACPRLAST : out std_ulogic;
      SAXIACPRRESP : out std_logic_vector(1 downto 0);
      SAXIACPRVALID : out std_ulogic;
      SAXIACPWREADY : out std_ulogic;
      SAXIGP0ARREADY : out std_ulogic;
      SAXIGP0AWREADY : out std_ulogic;
      SAXIGP0BID : out std_logic_vector(5 downto 0);
      SAXIGP0BRESP : out std_logic_vector(1 downto 0);
      SAXIGP0BVALID : out std_ulogic;
      SAXIGP0RACOUNT : out std_logic_vector(3 downto 0);
      SAXIGP0RCOUNT : out std_logic_vector(7 downto 0);
      SAXIGP0RDATA : out std_logic_vector(127 downto 0);
      SAXIGP0RID : out std_logic_vector(5 downto 0);
      SAXIGP0RLAST : out std_ulogic;
      SAXIGP0RRESP : out std_logic_vector(1 downto 0);
      SAXIGP0RVALID : out std_ulogic;
      SAXIGP0WACOUNT : out std_logic_vector(3 downto 0);
      SAXIGP0WCOUNT : out std_logic_vector(7 downto 0);
      SAXIGP0WREADY : out std_ulogic;
      SAXIGP1ARREADY : out std_ulogic;
      SAXIGP1AWREADY : out std_ulogic;
      SAXIGP1BID : out std_logic_vector(5 downto 0);
      SAXIGP1BRESP : out std_logic_vector(1 downto 0);
      SAXIGP1BVALID : out std_ulogic;
      SAXIGP1RACOUNT : out std_logic_vector(3 downto 0);
      SAXIGP1RCOUNT : out std_logic_vector(7 downto 0);
      SAXIGP1RDATA : out std_logic_vector(127 downto 0);
      SAXIGP1RID : out std_logic_vector(5 downto 0);
      SAXIGP1RLAST : out std_ulogic;
      SAXIGP1RRESP : out std_logic_vector(1 downto 0);
      SAXIGP1RVALID : out std_ulogic;
      SAXIGP1WACOUNT : out std_logic_vector(3 downto 0);
      SAXIGP1WCOUNT : out std_logic_vector(7 downto 0);
      SAXIGP1WREADY : out std_ulogic;
      SAXIGP2ARREADY : out std_ulogic;
      SAXIGP2AWREADY : out std_ulogic;
      SAXIGP2BID : out std_logic_vector(5 downto 0);
      SAXIGP2BRESP : out std_logic_vector(1 downto 0);
      SAXIGP2BVALID : out std_ulogic;
      SAXIGP2RACOUNT : out std_logic_vector(3 downto 0);
      SAXIGP2RCOUNT : out std_logic_vector(7 downto 0);
      SAXIGP2RDATA : out std_logic_vector(127 downto 0);
      SAXIGP2RID : out std_logic_vector(5 downto 0);
      SAXIGP2RLAST : out std_ulogic;
      SAXIGP2RRESP : out std_logic_vector(1 downto 0);
      SAXIGP2RVALID : out std_ulogic;
      SAXIGP2WACOUNT : out std_logic_vector(3 downto 0);
      SAXIGP2WCOUNT : out std_logic_vector(7 downto 0);
      SAXIGP2WREADY : out std_ulogic;
      SAXIGP3ARREADY : out std_ulogic;
      SAXIGP3AWREADY : out std_ulogic;
      SAXIGP3BID : out std_logic_vector(5 downto 0);
      SAXIGP3BRESP : out std_logic_vector(1 downto 0);
      SAXIGP3BVALID : out std_ulogic;
      SAXIGP3RACOUNT : out std_logic_vector(3 downto 0);
      SAXIGP3RCOUNT : out std_logic_vector(7 downto 0);
      SAXIGP3RDATA : out std_logic_vector(127 downto 0);
      SAXIGP3RID : out std_logic_vector(5 downto 0);
      SAXIGP3RLAST : out std_ulogic;
      SAXIGP3RRESP : out std_logic_vector(1 downto 0);
      SAXIGP3RVALID : out std_ulogic;
      SAXIGP3WACOUNT : out std_logic_vector(3 downto 0);
      SAXIGP3WCOUNT : out std_logic_vector(7 downto 0);
      SAXIGP3WREADY : out std_ulogic;
      SAXIGP4ARREADY : out std_ulogic;
      SAXIGP4AWREADY : out std_ulogic;
      SAXIGP4BID : out std_logic_vector(5 downto 0);
      SAXIGP4BRESP : out std_logic_vector(1 downto 0);
      SAXIGP4BVALID : out std_ulogic;
      SAXIGP4RACOUNT : out std_logic_vector(3 downto 0);
      SAXIGP4RCOUNT : out std_logic_vector(7 downto 0);
      SAXIGP4RDATA : out std_logic_vector(127 downto 0);
      SAXIGP4RID : out std_logic_vector(5 downto 0);
      SAXIGP4RLAST : out std_ulogic;
      SAXIGP4RRESP : out std_logic_vector(1 downto 0);
      SAXIGP4RVALID : out std_ulogic;
      SAXIGP4WACOUNT : out std_logic_vector(3 downto 0);
      SAXIGP4WCOUNT : out std_logic_vector(7 downto 0);
      SAXIGP4WREADY : out std_ulogic;
      SAXIGP5ARREADY : out std_ulogic;
      SAXIGP5AWREADY : out std_ulogic;
      SAXIGP5BID : out std_logic_vector(5 downto 0);
      SAXIGP5BRESP : out std_logic_vector(1 downto 0);
      SAXIGP5BVALID : out std_ulogic;
      SAXIGP5RACOUNT : out std_logic_vector(3 downto 0);
      SAXIGP5RCOUNT : out std_logic_vector(7 downto 0);
      SAXIGP5RDATA : out std_logic_vector(127 downto 0);
      SAXIGP5RID : out std_logic_vector(5 downto 0);
      SAXIGP5RLAST : out std_ulogic;
      SAXIGP5RRESP : out std_logic_vector(1 downto 0);
      SAXIGP5RVALID : out std_ulogic;
      SAXIGP5WACOUNT : out std_logic_vector(3 downto 0);
      SAXIGP5WCOUNT : out std_logic_vector(7 downto 0);
      SAXIGP5WREADY : out std_ulogic;
      SAXIGP6ARREADY : out std_ulogic;
      SAXIGP6AWREADY : out std_ulogic;
      SAXIGP6BID : out std_logic_vector(5 downto 0);
      SAXIGP6BRESP : out std_logic_vector(1 downto 0);
      SAXIGP6BVALID : out std_ulogic;
      SAXIGP6RACOUNT : out std_logic_vector(3 downto 0);
      SAXIGP6RCOUNT : out std_logic_vector(7 downto 0);
      SAXIGP6RDATA : out std_logic_vector(127 downto 0);
      SAXIGP6RID : out std_logic_vector(5 downto 0);
      SAXIGP6RLAST : out std_ulogic;
      SAXIGP6RRESP : out std_logic_vector(1 downto 0);
      SAXIGP6RVALID : out std_ulogic;
      SAXIGP6WACOUNT : out std_logic_vector(3 downto 0);
      SAXIGP6WCOUNT : out std_logic_vector(7 downto 0);
      SAXIGP6WREADY : out std_ulogic;
      ADMAFCICLK : in std_logic_vector(7 downto 0);
      AIBPMUAFIFMFPDACK : in std_ulogic;
      AIBPMUAFIFMLPDACK : in std_ulogic;
      DDRCEXTREFRESHRANK0REQ : in std_ulogic;
      DDRCEXTREFRESHRANK1REQ : in std_ulogic;
      DDRCREFRESHPLCLK : in std_ulogic;
      DPAUXDATAIN : in std_ulogic;
      DPEXTERNALCUSTOMEVENT1 : in std_ulogic;
      DPEXTERNALCUSTOMEVENT2 : in std_ulogic;
      DPEXTERNALVSYNCEVENT : in std_ulogic;
      DPHOTPLUGDETECT : in std_ulogic;
      DPLIVEGFXALPHAIN : in std_logic_vector(7 downto 0);
      DPLIVEGFXPIXEL1IN : in std_logic_vector(35 downto 0);
      DPLIVEVIDEOINDE : in std_ulogic;
      DPLIVEVIDEOINHSYNC : in std_ulogic;
      DPLIVEVIDEOINPIXEL1 : in std_logic_vector(35 downto 0);
      DPLIVEVIDEOINVSYNC : in std_ulogic;
      DPMAXISMIXEDAUDIOTREADY : in std_ulogic;
      DPSAXISAUDIOCLK : in std_ulogic;
      DPSAXISAUDIOTDATA : in std_logic_vector(31 downto 0);
      DPSAXISAUDIOTID : in std_ulogic;
      DPSAXISAUDIOTVALID : in std_ulogic;
      DPVIDEOINCLK : in std_ulogic;
      EMIOCAN0PHYRX : in std_ulogic;
      EMIOCAN1PHYRX : in std_ulogic;
      EMIOENET0DMATXSTATUSTOG : in std_ulogic;
      EMIOENET0EXTINTIN : in std_ulogic;
      EMIOENET0GMIICOL : in std_ulogic;
      EMIOENET0GMIICRS : in std_ulogic;
      EMIOENET0GMIIRXCLK : in std_ulogic;
      EMIOENET0GMIIRXD : in std_logic_vector(7 downto 0);
      EMIOENET0GMIIRXDV : in std_ulogic;
      EMIOENET0GMIIRXER : in std_ulogic;
      EMIOENET0GMIITXCLK : in std_ulogic;
      EMIOENET0MDIOI : in std_ulogic;
      EMIOENET0RXWOVERFLOW : in std_ulogic;
      EMIOENET0TXRCONTROL : in std_ulogic;
      EMIOENET0TXRDATA : in std_logic_vector(7 downto 0);
      EMIOENET0TXRDATARDY : in std_ulogic;
      EMIOENET0TXREOP : in std_ulogic;
      EMIOENET0TXRERR : in std_ulogic;
      EMIOENET0TXRFLUSHED : in std_ulogic;
      EMIOENET0TXRSOP : in std_ulogic;
      EMIOENET0TXRUNDERFLOW : in std_ulogic;
      EMIOENET0TXRVALID : in std_ulogic;
      EMIOENET1DMATXSTATUSTOG : in std_ulogic;
      EMIOENET1EXTINTIN : in std_ulogic;
      EMIOENET1GMIICOL : in std_ulogic;
      EMIOENET1GMIICRS : in std_ulogic;
      EMIOENET1GMIIRXCLK : in std_ulogic;
      EMIOENET1GMIIRXD : in std_logic_vector(7 downto 0);
      EMIOENET1GMIIRXDV : in std_ulogic;
      EMIOENET1GMIIRXER : in std_ulogic;
      EMIOENET1GMIITXCLK : in std_ulogic;
      EMIOENET1MDIOI : in std_ulogic;
      EMIOENET1RXWOVERFLOW : in std_ulogic;
      EMIOENET1TXRCONTROL : in std_ulogic;
      EMIOENET1TXRDATA : in std_logic_vector(7 downto 0);
      EMIOENET1TXRDATARDY : in std_ulogic;
      EMIOENET1TXREOP : in std_ulogic;
      EMIOENET1TXRERR : in std_ulogic;
      EMIOENET1TXRFLUSHED : in std_ulogic;
      EMIOENET1TXRSOP : in std_ulogic;
      EMIOENET1TXRUNDERFLOW : in std_ulogic;
      EMIOENET1TXRVALID : in std_ulogic;
      EMIOENET2DMATXSTATUSTOG : in std_ulogic;
      EMIOENET2EXTINTIN : in std_ulogic;
      EMIOENET2GMIICOL : in std_ulogic;
      EMIOENET2GMIICRS : in std_ulogic;
      EMIOENET2GMIIRXCLK : in std_ulogic;
      EMIOENET2GMIIRXD : in std_logic_vector(7 downto 0);
      EMIOENET2GMIIRXDV : in std_ulogic;
      EMIOENET2GMIIRXER : in std_ulogic;
      EMIOENET2GMIITXCLK : in std_ulogic;
      EMIOENET2MDIOI : in std_ulogic;
      EMIOENET2RXWOVERFLOW : in std_ulogic;
      EMIOENET2TXRCONTROL : in std_ulogic;
      EMIOENET2TXRDATA : in std_logic_vector(7 downto 0);
      EMIOENET2TXRDATARDY : in std_ulogic;
      EMIOENET2TXREOP : in std_ulogic;
      EMIOENET2TXRERR : in std_ulogic;
      EMIOENET2TXRFLUSHED : in std_ulogic;
      EMIOENET2TXRSOP : in std_ulogic;
      EMIOENET2TXRUNDERFLOW : in std_ulogic;
      EMIOENET2TXRVALID : in std_ulogic;
      EMIOENET3DMATXSTATUSTOG : in std_ulogic;
      EMIOENET3EXTINTIN : in std_ulogic;
      EMIOENET3GMIICOL : in std_ulogic;
      EMIOENET3GMIICRS : in std_ulogic;
      EMIOENET3GMIIRXCLK : in std_ulogic;
      EMIOENET3GMIIRXD : in std_logic_vector(7 downto 0);
      EMIOENET3GMIIRXDV : in std_ulogic;
      EMIOENET3GMIIRXER : in std_ulogic;
      EMIOENET3GMIITXCLK : in std_ulogic;
      EMIOENET3MDIOI : in std_ulogic;
      EMIOENET3RXWOVERFLOW : in std_ulogic;
      EMIOENET3TXRCONTROL : in std_ulogic;
      EMIOENET3TXRDATA : in std_logic_vector(7 downto 0);
      EMIOENET3TXRDATARDY : in std_ulogic;
      EMIOENET3TXREOP : in std_ulogic;
      EMIOENET3TXRERR : in std_ulogic;
      EMIOENET3TXRFLUSHED : in std_ulogic;
      EMIOENET3TXRSOP : in std_ulogic;
      EMIOENET3TXRUNDERFLOW : in std_ulogic;
      EMIOENET3TXRVALID : in std_ulogic;
      EMIOENETTSUCLK : in std_ulogic;
      EMIOGEM0TSUINCCTRL : in std_logic_vector(1 downto 0);
      EMIOGEM1TSUINCCTRL : in std_logic_vector(1 downto 0);
      EMIOGEM2TSUINCCTRL : in std_logic_vector(1 downto 0);
      EMIOGEM3TSUINCCTRL : in std_logic_vector(1 downto 0);
      EMIOGPIOI : in std_logic_vector(95 downto 0);
      EMIOHUBPORTOVERCRNTUSB20 : in std_ulogic;
      EMIOHUBPORTOVERCRNTUSB21 : in std_ulogic;
      EMIOHUBPORTOVERCRNTUSB30 : in std_ulogic;
      EMIOHUBPORTOVERCRNTUSB31 : in std_ulogic;
      EMIOI2C0SCLI : in std_ulogic;
      EMIOI2C0SDAI : in std_ulogic;
      EMIOI2C1SCLI : in std_ulogic;
      EMIOI2C1SDAI : in std_ulogic;
      EMIOSDIO0CDN : in std_ulogic;
      EMIOSDIO0CMDIN : in std_ulogic;
      EMIOSDIO0DATAIN : in std_logic_vector(7 downto 0);
      EMIOSDIO0FBCLKIN : in std_ulogic;
      EMIOSDIO0WP : in std_ulogic;
      EMIOSDIO1CDN : in std_ulogic;
      EMIOSDIO1CMDIN : in std_ulogic;
      EMIOSDIO1DATAIN : in std_logic_vector(7 downto 0);
      EMIOSDIO1FBCLKIN : in std_ulogic;
      EMIOSDIO1WP : in std_ulogic;
      EMIOSPI0MI : in std_ulogic;
      EMIOSPI0SCLKI : in std_ulogic;
      EMIOSPI0SI : in std_ulogic;
      EMIOSPI0SSIN : in std_ulogic;
      EMIOSPI1MI : in std_ulogic;
      EMIOSPI1SCLKI : in std_ulogic;
      EMIOSPI1SI : in std_ulogic;
      EMIOSPI1SSIN : in std_ulogic;
      EMIOTTC0CLKI : in std_logic_vector(2 downto 0);
      EMIOTTC1CLKI : in std_logic_vector(2 downto 0);
      EMIOTTC2CLKI : in std_logic_vector(2 downto 0);
      EMIOTTC3CLKI : in std_logic_vector(2 downto 0);
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
      EMIOWDT0CLKI : in std_ulogic;
      EMIOWDT1CLKI : in std_ulogic;
      FMIOGEM0FIFORXCLKFROMPL : in std_ulogic;
      FMIOGEM0FIFOTXCLKFROMPL : in std_ulogic;
      FMIOGEM0SIGNALDETECT : in std_ulogic;
      FMIOGEM1FIFORXCLKFROMPL : in std_ulogic;
      FMIOGEM1FIFOTXCLKFROMPL : in std_ulogic;
      FMIOGEM1SIGNALDETECT : in std_ulogic;
      FMIOGEM2FIFORXCLKFROMPL : in std_ulogic;
      FMIOGEM2FIFOTXCLKFROMPL : in std_ulogic;
      FMIOGEM2SIGNALDETECT : in std_ulogic;
      FMIOGEM3FIFORXCLKFROMPL : in std_ulogic;
      FMIOGEM3FIFOTXCLKFROMPL : in std_ulogic;
      FMIOGEM3SIGNALDETECT : in std_ulogic;
      FMIOGEMTSUCLKFROMPL : in std_ulogic;
      FTMGPI : in std_logic_vector(31 downto 0);
      GDMAFCICLK : in std_logic_vector(7 downto 0);
      MAXIGP0ACLK : in std_ulogic;
      MAXIGP0ARREADY : in std_ulogic;
      MAXIGP0AWREADY : in std_ulogic;
      MAXIGP0BID : in std_logic_vector(15 downto 0);
      MAXIGP0BRESP : in std_logic_vector(1 downto 0);
      MAXIGP0BVALID : in std_ulogic;
      MAXIGP0RDATA : in std_logic_vector(127 downto 0);
      MAXIGP0RID : in std_logic_vector(15 downto 0);
      MAXIGP0RLAST : in std_ulogic;
      MAXIGP0RRESP : in std_logic_vector(1 downto 0);
      MAXIGP0RVALID : in std_ulogic;
      MAXIGP0WREADY : in std_ulogic;
      MAXIGP1ACLK : in std_ulogic;
      MAXIGP1ARREADY : in std_ulogic;
      MAXIGP1AWREADY : in std_ulogic;
      MAXIGP1BID : in std_logic_vector(15 downto 0);
      MAXIGP1BRESP : in std_logic_vector(1 downto 0);
      MAXIGP1BVALID : in std_ulogic;
      MAXIGP1RDATA : in std_logic_vector(127 downto 0);
      MAXIGP1RID : in std_logic_vector(15 downto 0);
      MAXIGP1RLAST : in std_ulogic;
      MAXIGP1RRESP : in std_logic_vector(1 downto 0);
      MAXIGP1RVALID : in std_ulogic;
      MAXIGP1WREADY : in std_ulogic;
      MAXIGP2ACLK : in std_ulogic;
      MAXIGP2ARREADY : in std_ulogic;
      MAXIGP2AWREADY : in std_ulogic;
      MAXIGP2BID : in std_logic_vector(15 downto 0);
      MAXIGP2BRESP : in std_logic_vector(1 downto 0);
      MAXIGP2BVALID : in std_ulogic;
      MAXIGP2RDATA : in std_logic_vector(127 downto 0);
      MAXIGP2RID : in std_logic_vector(15 downto 0);
      MAXIGP2RLAST : in std_ulogic;
      MAXIGP2RRESP : in std_logic_vector(1 downto 0);
      MAXIGP2RVALID : in std_ulogic;
      MAXIGP2WREADY : in std_ulogic;
      NFIQ0LPDRPU : in std_ulogic;
      NFIQ1LPDRPU : in std_ulogic;
      NIRQ0LPDRPU : in std_ulogic;
      NIRQ1LPDRPU : in std_ulogic;
      PL2ADMACVLD : in std_logic_vector(7 downto 0);
      PL2ADMATACK : in std_logic_vector(7 downto 0);
      PL2GDMACVLD : in std_logic_vector(7 downto 0);
      PL2GDMATACK : in std_logic_vector(7 downto 0);
      PLACECLK : in std_ulogic;
      PLACPINACT : in std_ulogic;
      PLFPGASTOP : in std_logic_vector(3 downto 0);
      PLLAUXREFCLKFPD : in std_logic_vector(2 downto 0);
      PLLAUXREFCLKLPD : in std_logic_vector(1 downto 0);
      PLPMUGPI : in std_logic_vector(31 downto 0);
      PLPSAPUGICFIQ : in std_logic_vector(3 downto 0);
      PLPSAPUGICIRQ : in std_logic_vector(3 downto 0);
      PLPSEVENTI : in std_ulogic;
      PLPSIRQ0 : in std_logic_vector(7 downto 0);
      PLPSIRQ1 : in std_logic_vector(7 downto 0);
      PLPSTRACECLK : in std_ulogic;
      PLPSTRIGACK : in std_logic_vector(3 downto 0);
      PLPSTRIGGER : in std_logic_vector(3 downto 0);
      PMUERRORFROMPL : in std_logic_vector(3 downto 0);
      RPUEVENTI0 : in std_ulogic;
      RPUEVENTI1 : in std_ulogic;
      SACEFPDACREADY : in std_ulogic;
      SACEFPDARADDR : in std_logic_vector(43 downto 0);
      SACEFPDARBAR : in std_logic_vector(1 downto 0);
      SACEFPDARBURST : in std_logic_vector(1 downto 0);
      SACEFPDARCACHE : in std_logic_vector(3 downto 0);
      SACEFPDARDOMAIN : in std_logic_vector(1 downto 0);
      SACEFPDARID : in std_logic_vector(5 downto 0);
      SACEFPDARLEN : in std_logic_vector(7 downto 0);
      SACEFPDARLOCK : in std_ulogic;
      SACEFPDARPROT : in std_logic_vector(2 downto 0);
      SACEFPDARQOS : in std_logic_vector(3 downto 0);
      SACEFPDARREGION : in std_logic_vector(3 downto 0);
      SACEFPDARSIZE : in std_logic_vector(2 downto 0);
      SACEFPDARSNOOP : in std_logic_vector(3 downto 0);
      SACEFPDARUSER : in std_logic_vector(15 downto 0);
      SACEFPDARVALID : in std_ulogic;
      SACEFPDAWADDR : in std_logic_vector(43 downto 0);
      SACEFPDAWBAR : in std_logic_vector(1 downto 0);
      SACEFPDAWBURST : in std_logic_vector(1 downto 0);
      SACEFPDAWCACHE : in std_logic_vector(3 downto 0);
      SACEFPDAWDOMAIN : in std_logic_vector(1 downto 0);
      SACEFPDAWID : in std_logic_vector(5 downto 0);
      SACEFPDAWLEN : in std_logic_vector(7 downto 0);
      SACEFPDAWLOCK : in std_ulogic;
      SACEFPDAWPROT : in std_logic_vector(2 downto 0);
      SACEFPDAWQOS : in std_logic_vector(3 downto 0);
      SACEFPDAWREGION : in std_logic_vector(3 downto 0);
      SACEFPDAWSIZE : in std_logic_vector(2 downto 0);
      SACEFPDAWSNOOP : in std_logic_vector(2 downto 0);
      SACEFPDAWUSER : in std_logic_vector(15 downto 0);
      SACEFPDAWVALID : in std_ulogic;
      SACEFPDBREADY : in std_ulogic;
      SACEFPDCDDATA : in std_logic_vector(127 downto 0);
      SACEFPDCDLAST : in std_ulogic;
      SACEFPDCDVALID : in std_ulogic;
      SACEFPDCRRESP : in std_logic_vector(4 downto 0);
      SACEFPDCRVALID : in std_ulogic;
      SACEFPDRACK : in std_ulogic;
      SACEFPDRREADY : in std_ulogic;
      SACEFPDWACK : in std_ulogic;
      SACEFPDWDATA : in std_logic_vector(127 downto 0);
      SACEFPDWLAST : in std_ulogic;
      SACEFPDWSTRB : in std_logic_vector(15 downto 0);
      SACEFPDWUSER : in std_ulogic;
      SACEFPDWVALID : in std_ulogic;
      SAXIACPACLK : in std_ulogic;
      SAXIACPARADDR : in std_logic_vector(39 downto 0);
      SAXIACPARBURST : in std_logic_vector(1 downto 0);
      SAXIACPARCACHE : in std_logic_vector(3 downto 0);
      SAXIACPARID : in std_logic_vector(4 downto 0);
      SAXIACPARLEN : in std_logic_vector(7 downto 0);
      SAXIACPARLOCK : in std_ulogic;
      SAXIACPARPROT : in std_logic_vector(2 downto 0);
      SAXIACPARQOS : in std_logic_vector(3 downto 0);
      SAXIACPARSIZE : in std_logic_vector(2 downto 0);
      SAXIACPARUSER : in std_logic_vector(1 downto 0);
      SAXIACPARVALID : in std_ulogic;
      SAXIACPAWADDR : in std_logic_vector(39 downto 0);
      SAXIACPAWBURST : in std_logic_vector(1 downto 0);
      SAXIACPAWCACHE : in std_logic_vector(3 downto 0);
      SAXIACPAWID : in std_logic_vector(4 downto 0);
      SAXIACPAWLEN : in std_logic_vector(7 downto 0);
      SAXIACPAWLOCK : in std_ulogic;
      SAXIACPAWPROT : in std_logic_vector(2 downto 0);
      SAXIACPAWQOS : in std_logic_vector(3 downto 0);
      SAXIACPAWSIZE : in std_logic_vector(2 downto 0);
      SAXIACPAWUSER : in std_logic_vector(1 downto 0);
      SAXIACPAWVALID : in std_ulogic;
      SAXIACPBREADY : in std_ulogic;
      SAXIACPRREADY : in std_ulogic;
      SAXIACPWDATA : in std_logic_vector(127 downto 0);
      SAXIACPWLAST : in std_ulogic;
      SAXIACPWSTRB : in std_logic_vector(15 downto 0);
      SAXIACPWVALID : in std_ulogic;
      SAXIGP0ARADDR : in std_logic_vector(48 downto 0);
      SAXIGP0ARBURST : in std_logic_vector(1 downto 0);
      SAXIGP0ARCACHE : in std_logic_vector(3 downto 0);
      SAXIGP0ARID : in std_logic_vector(5 downto 0);
      SAXIGP0ARLEN : in std_logic_vector(7 downto 0);
      SAXIGP0ARLOCK : in std_ulogic;
      SAXIGP0ARPROT : in std_logic_vector(2 downto 0);
      SAXIGP0ARQOS : in std_logic_vector(3 downto 0);
      SAXIGP0ARSIZE : in std_logic_vector(2 downto 0);
      SAXIGP0ARUSER : in std_ulogic;
      SAXIGP0ARVALID : in std_ulogic;
      SAXIGP0AWADDR : in std_logic_vector(48 downto 0);
      SAXIGP0AWBURST : in std_logic_vector(1 downto 0);
      SAXIGP0AWCACHE : in std_logic_vector(3 downto 0);
      SAXIGP0AWID : in std_logic_vector(5 downto 0);
      SAXIGP0AWLEN : in std_logic_vector(7 downto 0);
      SAXIGP0AWLOCK : in std_ulogic;
      SAXIGP0AWPROT : in std_logic_vector(2 downto 0);
      SAXIGP0AWQOS : in std_logic_vector(3 downto 0);
      SAXIGP0AWSIZE : in std_logic_vector(2 downto 0);
      SAXIGP0AWUSER : in std_ulogic;
      SAXIGP0AWVALID : in std_ulogic;
      SAXIGP0BREADY : in std_ulogic;
      SAXIGP0RCLK : in std_ulogic;
      SAXIGP0RREADY : in std_ulogic;
      SAXIGP0WCLK : in std_ulogic;
      SAXIGP0WDATA : in std_logic_vector(127 downto 0);
      SAXIGP0WLAST : in std_ulogic;
      SAXIGP0WSTRB : in std_logic_vector(15 downto 0);
      SAXIGP0WVALID : in std_ulogic;
      SAXIGP1ARADDR : in std_logic_vector(48 downto 0);
      SAXIGP1ARBURST : in std_logic_vector(1 downto 0);
      SAXIGP1ARCACHE : in std_logic_vector(3 downto 0);
      SAXIGP1ARID : in std_logic_vector(5 downto 0);
      SAXIGP1ARLEN : in std_logic_vector(7 downto 0);
      SAXIGP1ARLOCK : in std_ulogic;
      SAXIGP1ARPROT : in std_logic_vector(2 downto 0);
      SAXIGP1ARQOS : in std_logic_vector(3 downto 0);
      SAXIGP1ARSIZE : in std_logic_vector(2 downto 0);
      SAXIGP1ARUSER : in std_ulogic;
      SAXIGP1ARVALID : in std_ulogic;
      SAXIGP1AWADDR : in std_logic_vector(48 downto 0);
      SAXIGP1AWBURST : in std_logic_vector(1 downto 0);
      SAXIGP1AWCACHE : in std_logic_vector(3 downto 0);
      SAXIGP1AWID : in std_logic_vector(5 downto 0);
      SAXIGP1AWLEN : in std_logic_vector(7 downto 0);
      SAXIGP1AWLOCK : in std_ulogic;
      SAXIGP1AWPROT : in std_logic_vector(2 downto 0);
      SAXIGP1AWQOS : in std_logic_vector(3 downto 0);
      SAXIGP1AWSIZE : in std_logic_vector(2 downto 0);
      SAXIGP1AWUSER : in std_ulogic;
      SAXIGP1AWVALID : in std_ulogic;
      SAXIGP1BREADY : in std_ulogic;
      SAXIGP1RCLK : in std_ulogic;
      SAXIGP1RREADY : in std_ulogic;
      SAXIGP1WCLK : in std_ulogic;
      SAXIGP1WDATA : in std_logic_vector(127 downto 0);
      SAXIGP1WLAST : in std_ulogic;
      SAXIGP1WSTRB : in std_logic_vector(15 downto 0);
      SAXIGP1WVALID : in std_ulogic;
      SAXIGP2ARADDR : in std_logic_vector(48 downto 0);
      SAXIGP2ARBURST : in std_logic_vector(1 downto 0);
      SAXIGP2ARCACHE : in std_logic_vector(3 downto 0);
      SAXIGP2ARID : in std_logic_vector(5 downto 0);
      SAXIGP2ARLEN : in std_logic_vector(7 downto 0);
      SAXIGP2ARLOCK : in std_ulogic;
      SAXIGP2ARPROT : in std_logic_vector(2 downto 0);
      SAXIGP2ARQOS : in std_logic_vector(3 downto 0);
      SAXIGP2ARSIZE : in std_logic_vector(2 downto 0);
      SAXIGP2ARUSER : in std_ulogic;
      SAXIGP2ARVALID : in std_ulogic;
      SAXIGP2AWADDR : in std_logic_vector(48 downto 0);
      SAXIGP2AWBURST : in std_logic_vector(1 downto 0);
      SAXIGP2AWCACHE : in std_logic_vector(3 downto 0);
      SAXIGP2AWID : in std_logic_vector(5 downto 0);
      SAXIGP2AWLEN : in std_logic_vector(7 downto 0);
      SAXIGP2AWLOCK : in std_ulogic;
      SAXIGP2AWPROT : in std_logic_vector(2 downto 0);
      SAXIGP2AWQOS : in std_logic_vector(3 downto 0);
      SAXIGP2AWSIZE : in std_logic_vector(2 downto 0);
      SAXIGP2AWUSER : in std_ulogic;
      SAXIGP2AWVALID : in std_ulogic;
      SAXIGP2BREADY : in std_ulogic;
      SAXIGP2RCLK : in std_ulogic;
      SAXIGP2RREADY : in std_ulogic;
      SAXIGP2WCLK : in std_ulogic;
      SAXIGP2WDATA : in std_logic_vector(127 downto 0);
      SAXIGP2WLAST : in std_ulogic;
      SAXIGP2WSTRB : in std_logic_vector(15 downto 0);
      SAXIGP2WVALID : in std_ulogic;
      SAXIGP3ARADDR : in std_logic_vector(48 downto 0);
      SAXIGP3ARBURST : in std_logic_vector(1 downto 0);
      SAXIGP3ARCACHE : in std_logic_vector(3 downto 0);
      SAXIGP3ARID : in std_logic_vector(5 downto 0);
      SAXIGP3ARLEN : in std_logic_vector(7 downto 0);
      SAXIGP3ARLOCK : in std_ulogic;
      SAXIGP3ARPROT : in std_logic_vector(2 downto 0);
      SAXIGP3ARQOS : in std_logic_vector(3 downto 0);
      SAXIGP3ARSIZE : in std_logic_vector(2 downto 0);
      SAXIGP3ARUSER : in std_ulogic;
      SAXIGP3ARVALID : in std_ulogic;
      SAXIGP3AWADDR : in std_logic_vector(48 downto 0);
      SAXIGP3AWBURST : in std_logic_vector(1 downto 0);
      SAXIGP3AWCACHE : in std_logic_vector(3 downto 0);
      SAXIGP3AWID : in std_logic_vector(5 downto 0);
      SAXIGP3AWLEN : in std_logic_vector(7 downto 0);
      SAXIGP3AWLOCK : in std_ulogic;
      SAXIGP3AWPROT : in std_logic_vector(2 downto 0);
      SAXIGP3AWQOS : in std_logic_vector(3 downto 0);
      SAXIGP3AWSIZE : in std_logic_vector(2 downto 0);
      SAXIGP3AWUSER : in std_ulogic;
      SAXIGP3AWVALID : in std_ulogic;
      SAXIGP3BREADY : in std_ulogic;
      SAXIGP3RCLK : in std_ulogic;
      SAXIGP3RREADY : in std_ulogic;
      SAXIGP3WCLK : in std_ulogic;
      SAXIGP3WDATA : in std_logic_vector(127 downto 0);
      SAXIGP3WLAST : in std_ulogic;
      SAXIGP3WSTRB : in std_logic_vector(15 downto 0);
      SAXIGP3WVALID : in std_ulogic;
      SAXIGP4ARADDR : in std_logic_vector(48 downto 0);
      SAXIGP4ARBURST : in std_logic_vector(1 downto 0);
      SAXIGP4ARCACHE : in std_logic_vector(3 downto 0);
      SAXIGP4ARID : in std_logic_vector(5 downto 0);
      SAXIGP4ARLEN : in std_logic_vector(7 downto 0);
      SAXIGP4ARLOCK : in std_ulogic;
      SAXIGP4ARPROT : in std_logic_vector(2 downto 0);
      SAXIGP4ARQOS : in std_logic_vector(3 downto 0);
      SAXIGP4ARSIZE : in std_logic_vector(2 downto 0);
      SAXIGP4ARUSER : in std_ulogic;
      SAXIGP4ARVALID : in std_ulogic;
      SAXIGP4AWADDR : in std_logic_vector(48 downto 0);
      SAXIGP4AWBURST : in std_logic_vector(1 downto 0);
      SAXIGP4AWCACHE : in std_logic_vector(3 downto 0);
      SAXIGP4AWID : in std_logic_vector(5 downto 0);
      SAXIGP4AWLEN : in std_logic_vector(7 downto 0);
      SAXIGP4AWLOCK : in std_ulogic;
      SAXIGP4AWPROT : in std_logic_vector(2 downto 0);
      SAXIGP4AWQOS : in std_logic_vector(3 downto 0);
      SAXIGP4AWSIZE : in std_logic_vector(2 downto 0);
      SAXIGP4AWUSER : in std_ulogic;
      SAXIGP4AWVALID : in std_ulogic;
      SAXIGP4BREADY : in std_ulogic;
      SAXIGP4RCLK : in std_ulogic;
      SAXIGP4RREADY : in std_ulogic;
      SAXIGP4WCLK : in std_ulogic;
      SAXIGP4WDATA : in std_logic_vector(127 downto 0);
      SAXIGP4WLAST : in std_ulogic;
      SAXIGP4WSTRB : in std_logic_vector(15 downto 0);
      SAXIGP4WVALID : in std_ulogic;
      SAXIGP5ARADDR : in std_logic_vector(48 downto 0);
      SAXIGP5ARBURST : in std_logic_vector(1 downto 0);
      SAXIGP5ARCACHE : in std_logic_vector(3 downto 0);
      SAXIGP5ARID : in std_logic_vector(5 downto 0);
      SAXIGP5ARLEN : in std_logic_vector(7 downto 0);
      SAXIGP5ARLOCK : in std_ulogic;
      SAXIGP5ARPROT : in std_logic_vector(2 downto 0);
      SAXIGP5ARQOS : in std_logic_vector(3 downto 0);
      SAXIGP5ARSIZE : in std_logic_vector(2 downto 0);
      SAXIGP5ARUSER : in std_ulogic;
      SAXIGP5ARVALID : in std_ulogic;
      SAXIGP5AWADDR : in std_logic_vector(48 downto 0);
      SAXIGP5AWBURST : in std_logic_vector(1 downto 0);
      SAXIGP5AWCACHE : in std_logic_vector(3 downto 0);
      SAXIGP5AWID : in std_logic_vector(5 downto 0);
      SAXIGP5AWLEN : in std_logic_vector(7 downto 0);
      SAXIGP5AWLOCK : in std_ulogic;
      SAXIGP5AWPROT : in std_logic_vector(2 downto 0);
      SAXIGP5AWQOS : in std_logic_vector(3 downto 0);
      SAXIGP5AWSIZE : in std_logic_vector(2 downto 0);
      SAXIGP5AWUSER : in std_ulogic;
      SAXIGP5AWVALID : in std_ulogic;
      SAXIGP5BREADY : in std_ulogic;
      SAXIGP5RCLK : in std_ulogic;
      SAXIGP5RREADY : in std_ulogic;
      SAXIGP5WCLK : in std_ulogic;
      SAXIGP5WDATA : in std_logic_vector(127 downto 0);
      SAXIGP5WLAST : in std_ulogic;
      SAXIGP5WSTRB : in std_logic_vector(15 downto 0);
      SAXIGP5WVALID : in std_ulogic;
      SAXIGP6ARADDR : in std_logic_vector(48 downto 0);
      SAXIGP6ARBURST : in std_logic_vector(1 downto 0);
      SAXIGP6ARCACHE : in std_logic_vector(3 downto 0);
      SAXIGP6ARID : in std_logic_vector(5 downto 0);
      SAXIGP6ARLEN : in std_logic_vector(7 downto 0);
      SAXIGP6ARLOCK : in std_ulogic;
      SAXIGP6ARPROT : in std_logic_vector(2 downto 0);
      SAXIGP6ARQOS : in std_logic_vector(3 downto 0);
      SAXIGP6ARSIZE : in std_logic_vector(2 downto 0);
      SAXIGP6ARUSER : in std_ulogic;
      SAXIGP6ARVALID : in std_ulogic;
      SAXIGP6AWADDR : in std_logic_vector(48 downto 0);
      SAXIGP6AWBURST : in std_logic_vector(1 downto 0);
      SAXIGP6AWCACHE : in std_logic_vector(3 downto 0);
      SAXIGP6AWID : in std_logic_vector(5 downto 0);
      SAXIGP6AWLEN : in std_logic_vector(7 downto 0);
      SAXIGP6AWLOCK : in std_ulogic;
      SAXIGP6AWPROT : in std_logic_vector(2 downto 0);
      SAXIGP6AWQOS : in std_logic_vector(3 downto 0);
      SAXIGP6AWSIZE : in std_logic_vector(2 downto 0);
      SAXIGP6AWUSER : in std_ulogic;
      SAXIGP6AWVALID : in std_ulogic;
      SAXIGP6BREADY : in std_ulogic;
      SAXIGP6RCLK : in std_ulogic;
      SAXIGP6RREADY : in std_ulogic;
      SAXIGP6WCLK : in std_ulogic;
      SAXIGP6WDATA : in std_logic_vector(127 downto 0);
      SAXIGP6WLAST : in std_ulogic;
      SAXIGP6WSTRB : in std_logic_vector(15 downto 0);
      SAXIGP6WVALID : in std_ulogic;
      STMEVENT : in std_logic_vector(59 downto 0)
      );
  end component;
  attribute BOX_TYPE of
    PS8 : component is "PRIMITIVE";

  component BUFG_PS is
    port(
      O : out std_ulogic;
      I : in std_ulogic
      );
  end component;
  attribute BOX_TYPE of
    BUFG_PS : component is "PRIMITIVE";

  -- Vivado sees no side effect in the PS8 cell: in a design where PL
  -- logic only talks to the PS, without PL I/O, opt_design would sweep
  -- the PS8 and all the logic around it.
  attribute DONT_TOUCH : string;
  attribute DONT_TOUCH of ps : label is "TRUE";

  -- AXI4 signals, as the PS8 primitive has them, sized for the widest
  -- of all AXI ports.  Each port uses the LSBs it has.
  constant ps_address_width_c : natural := 49;
  constant ps_id_width_c : natural := 16;
  constant ps_data_width_c : natural := 128;
  constant ps_user_width_c : natural := 2;

  type ps_addr_t is
  record
    addr: std_logic_vector(ps_address_width_c-1 downto 0);
    burst: std_logic_vector(1 downto 0);
    cache: std_logic_vector(3 downto 0);
    id: std_logic_vector(ps_id_width_c-1 downto 0);
    len: std_logic_vector(7 downto 0);
    lock: std_ulogic;
    prot: std_logic_vector(2 downto 0);
    qos: std_logic_vector(3 downto 0);
    size: std_logic_vector(2 downto 0);
    user: std_logic_vector(ps_user_width_c-1 downto 0);
    valid: std_ulogic;
  end record;

  -- Master-driven AXI4 signals.
  type ps_fwd_t is
  record
    aw: ps_addr_t;
    ar: ps_addr_t;
    wdata: std_logic_vector(ps_data_width_c-1 downto 0);
    wlast: std_ulogic;
    wstrb: std_logic_vector(ps_data_width_c/8-1 downto 0);
    wvalid: std_ulogic;
    bready: std_ulogic;
    rready: std_ulogic;
  end record;

  -- Slave-driven AXI4 signals.
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

  -- AFI FIFO levels, as the PS8 primitive has them.
  type afi_ps_level_t is
  record
    rcount: std_logic_vector(7 downto 0);
    wcount: std_logic_vector(7 downto 0);
    racount: std_logic_vector(3 downto 0);
    wacount: std_logic_vector(3 downto 0);
  end record;
  type afi_ps_level_vector is array (natural range <>) of afi_ps_level_t;

  type byte_vector is array (natural range <>) of std_logic_vector(7 downto 0);
  type pair_vector is array (natural range <>) of std_logic_vector(1 downto 0);

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
    assert cfg.data_bus_width_l2 >= 2
      and cfg.data_bus_width_l2 <= native.data_bus_width_l2
      report name & ": data width must be 32, 64 or 128"
      severity failure;
    assert cfg.address_width <= native.address_width
      report name & ": address width must be " & integer'image(native.address_width) & " or less"
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
  -- native one.
  function s_config_check(name: string; cfg, native: config_t) return boolean
  is
  begin
    assert cfg.data_bus_width_l2 >= 2
      and cfg.data_bus_width_l2 <= native.data_bus_width_l2
      report name & ": data width must be 32, 64 or 128"
      severity failure;
    assert cfg.address_width <= native.address_width
      report name & ": address width must be " & integer'image(native.address_width) & " or less"
      severity failure;
    assert cfg.id_width <= native.id_width
      report name & ": ID width must be " & integer'image(native.id_width) & " or less"
      severity failure;
    assert cfg.len_width <= native.len_width
      report name & ": max_length must be " & integer'image(2 ** native.len_width) & " or less"
      severity failure;
    assert cfg.user_width <= native.user_width
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
                   size_l2 => unsigned(a.size),
                   burst => to_burst(cfg, std_ulogic_vector(a.burst)),
                   lock => to_lock(cfg, lock_t'(0 => a.lock)),
                   cache => std_ulogic_vector(a.cache),
                   prot => std_ulogic_vector(a.prot),
                   qos => std_ulogic_vector(a.qos),
                   valid => a.valid = '1');
  end function;

  -- S_AXI_*: NSL address to PS
  function to_ps_addr(cfg: config_t; a: address_t) return ps_addr_t
  is
    variable ret: ps_addr_t;
    variable lck: lock_t;
  begin
    lck := to_logic(cfg, lock(cfg, a));
    ret.addr := std_logic_vector(resize(address(cfg, a), ret.addr'length));
    ret.burst := std_logic_vector(to_logic(cfg, burst(cfg, a)));
    ret.cache := std_logic_vector(cache(cfg, a));
    ret.id := std_logic_vector(resize(unsigned(id(cfg, a)), ret.id'length));
    ret.len := std_logic_vector(length_m1(cfg, a, ret.len'length));
    ret.lock := lck(0);
    ret.prot := std_logic_vector(prot(cfg, a));
    ret.qos := std_logic_vector(qos(cfg, a));
    ret.size := std_logic_vector(size_l2(cfg, a));
    ret.user := std_logic_vector(resize(unsigned(user(cfg, a)), ret.user'length));
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

  -- S_AXI_*: NSL master record to PS master signals
  function to_ps_fwd(cfg: config_t; m: master_t) return ps_fwd_t
  is
    constant dw: natural := data_width(cfg);
    variable ret: ps_fwd_t;
  begin
    ret.aw := to_ps_addr(cfg, m.aw);
    ret.ar := to_ps_addr(cfg, m.ar);
    ret.wdata := (others => '0');
    ret.wdata(dw-1 downto 0) := std_logic_vector(value(cfg, m.w, ENDIAN_LITTLE));
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

  -- M_AXI ports: HPM0_FPD, HPM1_FPD, HPM0_LPD (MAXIGP0 to 2)
  constant m_config_c : config_vector(0 to 2)
    := (m_axi_hpm0_fpd_config_c, m_axi_hpm1_fpd_config_c, m_axi_hpm0_lpd_config_c);
  -- S_AXI ports: HPC0_FPD, HPC1_FPD, HP0_FPD to HP3_FPD, LPD (SAXIGP0
  -- to 6, AFIFM0 to 6), then ACP_FPD
  constant s_config_c : config_vector(0 to 7)
    := (s_axi_hpc0_fpd_config_c, s_axi_hpc1_fpd_config_c,
        s_axi_hp0_fpd_config_c, s_axi_hp1_fpd_config_c,
        s_axi_hp2_fpd_config_c, s_axi_hp3_fpd_config_c,
        s_axi_lpd_config_c, s_axi_acp_fpd_config_c);

  constant m_hpm0_fpd_ok_c : boolean
    := m_config_check("M_AXI_HPM0_FPD", m_axi_hpm0_fpd_config_c, m_axi_config_c);
  constant m_hpm1_fpd_ok_c : boolean
    := m_config_check("M_AXI_HPM1_FPD", m_axi_hpm1_fpd_config_c, m_axi_config_c);
  constant m_hpm0_lpd_ok_c : boolean
    := m_config_check("M_AXI_HPM0_LPD", m_axi_hpm0_lpd_config_c, m_axi_config_c);
  constant s_hpc0_fpd_ok_c : boolean
    := s_config_check("S_AXI_HPC0_FPD", s_axi_hpc0_fpd_config_c, s_axi_config_c);
  constant s_hpc1_fpd_ok_c : boolean
    := s_config_check("S_AXI_HPC1_FPD", s_axi_hpc1_fpd_config_c, s_axi_config_c);
  constant s_hp0_fpd_ok_c : boolean
    := s_config_check("S_AXI_HP0_FPD", s_axi_hp0_fpd_config_c, s_axi_config_c);
  constant s_hp1_fpd_ok_c : boolean
    := s_config_check("S_AXI_HP1_FPD", s_axi_hp1_fpd_config_c, s_axi_config_c);
  constant s_hp2_fpd_ok_c : boolean
    := s_config_check("S_AXI_HP2_FPD", s_axi_hp2_fpd_config_c, s_axi_config_c);
  constant s_hp3_fpd_ok_c : boolean
    := s_config_check("S_AXI_HP3_FPD", s_axi_hp3_fpd_config_c, s_axi_config_c);
  constant s_lpd_ok_c : boolean
    := s_config_check("S_AXI_LPD", s_axi_lpd_config_c, s_axi_config_c);
  constant s_acp_fpd_ok_c : boolean
    := s_config_check("S_AXI_ACP_FPD", s_axi_acp_fpd_config_c,
                      nsl_xilinx.ps8.s_axi_acp_config_c);

  -- Hexadecimal digits of v, MSB first.
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

  -- Reported registers are given as a 16-bit page and a 16-bit
  -- offset, so that addresses fit in naturals.
  function register_note(page, offset, mask, value: natural; comment: string)
    return string
  is
  begin
    return "nsl_xilinx.ps8: write 0x" & hex(page, 4) & hex(offset, 4)
      & " mask 0x" & hex(mask, 8) & " value 0x" & hex(value, 8)
      & " # " & comment;
  end function;

  -- Data width field value for FPD_SLCR/LPD_SLCR AFI_FS DW_SSn_SEL:
  -- 0 for 32-bit, 1 for 64-bit, 2 for 128-bit.
  function afi_fs_width(cfg: config_t) return natural
  is
  begin
    return cfg.data_bus_width_l2 - 2;
  end function;

  -- Data width field value for AFIFM RDCTRL/WRCTRL FABRIC_WIDTH: 2 for
  -- 32-bit, 1 for 64-bit, 0 for 128-bit.
  function afifm_width(cfg: config_t) return natural
  is
  begin
    return 4 - cfg.data_bus_width_l2;
  end function;

  function width_comment(cfg: config_t) return string
  is
  begin
    return integer'image(data_width(cfg)) & "-bit";
  end function;

  -- AFIFM0 to 5 are in FPD at 0xFD360000 + n * 0x10000, AFIFM6 is in
  -- LPD at 0xFF9B0000.
  function afifm_page(n: natural) return natural
  is
  begin
    if n = 6 then
      return 16#FF9B#;
    end if;
    return 16#FD36# + n;
  end function;

  constant afifm_rdctrl_c : natural := 16#0000#;
  constant afifm_wrctrl_c : natural := 16#0014#;

  signal m_aclk: std_ulogic_vector(0 to 2);
  signal m_fwd: ps_fwd_vector(0 to 2);
  signal m_bwd: ps_bwd_vector(0 to 2);
  signal m_o: master_vector(0 to 2);
  signal m_i: slave_vector(0 to 2);
  signal s_aclk: std_ulogic_vector(0 to 7);
  signal s_fwd: ps_fwd_vector(0 to 7);
  signal s_bwd: ps_bwd_vector(0 to 7);
  signal s_i: master_vector(0 to 7);
  signal s_o: slave_vector(0 to 7);
  signal afi_level: afi_ps_level_vector(0 to 6);
  signal pl_clock_s: std_logic_vector(3 downto 0);
  signal adma_clock_s, adma_cvld_s, adma_tack_s, adma_cack_s, adma_tvld_s: std_logic_vector(7 downto 0);
  signal gdma_clock_s, gdma_cvld_s, gdma_tack_s, gdma_cack_s, gdma_tvld_s: std_logic_vector(7 downto 0);
  signal pl_ps_irq0_s, pl_ps_irq1_s: std_logic_vector(7 downto 0);
  signal ps_pl_irq_lpd_s: std_logic_vector(99 downto 0);
  signal ps_pl_irq_fpd_s: std_logic_vector(63 downto 0);
  signal gem_gmii_txd_s, gem_gmii_rxd_s: byte_vector(0 to 3);
  signal gem_tsu_inc_ctrl_s: pair_vector(0 to 3);
  signal gem_tsu_timer_s: std_logic_vector(93 downto 0);
  signal gem_tsu_ps_clock_s: std_ulogic;
  signal i2c0_scl_o_s, i2c0_scl_tn_s, i2c0_sda_o_s, i2c0_sda_tn_s: std_ulogic;
  signal i2c1_scl_o_s, i2c1_scl_tn_s, i2c1_sda_o_s, i2c1_sda_tn_s: std_ulogic;
  signal spi0_mo_s, spi0_motn_s, spi0_sclko_s, spi0_ssntn_s, spi0_mi_s: std_ulogic;
  signal spi0_sson_s: std_logic_vector(2 downto 0);
  signal spi0_selected_s: std_ulogic_vector(0 to spi0_slave_count_c-1);
  signal spi1_mo_s, spi1_motn_s, spi1_sclko_s, spi1_ssntn_s, spi1_mi_s: std_ulogic;
  signal spi1_sson_s: std_logic_vector(2 downto 0);
  signal spi1_selected_s: std_ulogic_vector(0 to spi1_slave_count_c-1);
  signal uart0_dtrn_s, uart0_rtsn_s, uart0_ctsn_s, uart0_dcdn_s, uart0_dsrn_s, uart0_rin_s: std_ulogic;
  signal uart1_dtrn_s, uart1_rtsn_s, uart1_ctsn_s, uart1_dcdn_s, uart1_dsrn_s, uart1_rin_s: std_ulogic;
  signal gpio_o_s, gpio_tn_s, gpio_i_s: std_logic_vector(95 downto 0);

  -- Whether slave index_c is selected, given PS8 SS outputs.  In
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

  ps: PS8
    port map(
      ADMA2PLCACK => adma_cack_s,
      ADMA2PLTVLD => adma_tvld_s,
      DPAUDIOREFCLK => open,
      DPAUXDATAOEN => open,
      DPAUXDATAOUT => open,
      DPLIVEVIDEODEOUT => open,
      DPMAXISMIXEDAUDIOTDATA => open,
      DPMAXISMIXEDAUDIOTID => open,
      DPMAXISMIXEDAUDIOTVALID => open,
      DPSAXISAUDIOTREADY => open,
      DPVIDEOOUTHSYNC => open,
      DPVIDEOOUTPIXEL1 => open,
      DPVIDEOOUTVSYNC => open,
      DPVIDEOREFCLK => open,
      EMIOCAN0PHYTX => open,
      EMIOCAN1PHYTX => open,
      EMIOENET0DMABUSWIDTH => open,
      EMIOENET0DMATXENDTOG => open,
      EMIOENET0GEMTSUTIMERCNT => gem_tsu_timer_s,
      EMIOENET0GMIITXD => gem_gmii_txd_s(0),
      EMIOENET0GMIITXEN => gem0_gmii_tx_o.en,
      EMIOENET0GMIITXER => gem0_gmii_tx_o.er,
      EMIOENET0MDIOMDC => gem0_smi_o.mdc,
      EMIOENET0MDIOO => gem0_smi_o.mdio.v,
      EMIOENET0MDIOTN => gem0_smi_o.mdio.output,
      EMIOENET0RXWDATA => open,
      EMIOENET0RXWEOP => open,
      EMIOENET0RXWERR => open,
      EMIOENET0RXWFLUSH => open,
      EMIOENET0RXWSOP => open,
      EMIOENET0RXWSTATUS => open,
      EMIOENET0RXWWR => open,
      EMIOENET0SPEEDMODE => open,
      EMIOENET0TXRRD => open,
      EMIOENET0TXRSTATUS => open,
      EMIOENET1DMABUSWIDTH => open,
      EMIOENET1DMATXENDTOG => open,
      EMIOENET1GMIITXD => gem_gmii_txd_s(1),
      EMIOENET1GMIITXEN => gem1_gmii_tx_o.en,
      EMIOENET1GMIITXER => gem1_gmii_tx_o.er,
      EMIOENET1MDIOMDC => gem1_smi_o.mdc,
      EMIOENET1MDIOO => gem1_smi_o.mdio.v,
      EMIOENET1MDIOTN => gem1_smi_o.mdio.output,
      EMIOENET1RXWDATA => open,
      EMIOENET1RXWEOP => open,
      EMIOENET1RXWERR => open,
      EMIOENET1RXWFLUSH => open,
      EMIOENET1RXWSOP => open,
      EMIOENET1RXWSTATUS => open,
      EMIOENET1RXWWR => open,
      EMIOENET1SPEEDMODE => open,
      EMIOENET1TXRRD => open,
      EMIOENET1TXRSTATUS => open,
      EMIOENET2DMABUSWIDTH => open,
      EMIOENET2DMATXENDTOG => open,
      EMIOENET2GMIITXD => gem_gmii_txd_s(2),
      EMIOENET2GMIITXEN => gem2_gmii_tx_o.en,
      EMIOENET2GMIITXER => gem2_gmii_tx_o.er,
      EMIOENET2MDIOMDC => gem2_smi_o.mdc,
      EMIOENET2MDIOO => gem2_smi_o.mdio.v,
      EMIOENET2MDIOTN => gem2_smi_o.mdio.output,
      EMIOENET2RXWDATA => open,
      EMIOENET2RXWEOP => open,
      EMIOENET2RXWERR => open,
      EMIOENET2RXWFLUSH => open,
      EMIOENET2RXWSOP => open,
      EMIOENET2RXWSTATUS => open,
      EMIOENET2RXWWR => open,
      EMIOENET2SPEEDMODE => open,
      EMIOENET2TXRRD => open,
      EMIOENET2TXRSTATUS => open,
      EMIOENET3DMABUSWIDTH => open,
      EMIOENET3DMATXENDTOG => open,
      EMIOENET3GMIITXD => gem_gmii_txd_s(3),
      EMIOENET3GMIITXEN => gem3_gmii_tx_o.en,
      EMIOENET3GMIITXER => gem3_gmii_tx_o.er,
      EMIOENET3MDIOMDC => gem3_smi_o.mdc,
      EMIOENET3MDIOO => gem3_smi_o.mdio.v,
      EMIOENET3MDIOTN => gem3_smi_o.mdio.output,
      EMIOENET3RXWDATA => open,
      EMIOENET3RXWEOP => open,
      EMIOENET3RXWERR => open,
      EMIOENET3RXWFLUSH => open,
      EMIOENET3RXWSOP => open,
      EMIOENET3RXWSTATUS => open,
      EMIOENET3RXWWR => open,
      EMIOENET3SPEEDMODE => open,
      EMIOENET3TXRRD => open,
      EMIOENET3TXRSTATUS => open,
      EMIOGEM0DELAYREQRX => gem0_ptp_rx_o.delay_req,
      EMIOGEM0DELAYREQTX => gem0_ptp_tx_o.delay_req,
      EMIOGEM0PDELAYREQRX => gem0_ptp_rx_o.pdelay_req,
      EMIOGEM0PDELAYREQTX => gem0_ptp_tx_o.pdelay_req,
      EMIOGEM0PDELAYRESPRX => gem0_ptp_rx_o.pdelay_resp,
      EMIOGEM0PDELAYRESPTX => gem0_ptp_tx_o.pdelay_resp,
      EMIOGEM0RXSOF => open,
      EMIOGEM0SYNCFRAMERX => gem0_ptp_rx_o.sync,
      EMIOGEM0SYNCFRAMETX => gem0_ptp_tx_o.sync,
      EMIOGEM0TSUTIMERCMPVAL => gem0_tsu_timer_cmp_val_o,
      EMIOGEM0TXRFIXEDLAT => open,
      EMIOGEM0TXSOF => open,
      EMIOGEM1DELAYREQRX => gem1_ptp_rx_o.delay_req,
      EMIOGEM1DELAYREQTX => gem1_ptp_tx_o.delay_req,
      EMIOGEM1PDELAYREQRX => gem1_ptp_rx_o.pdelay_req,
      EMIOGEM1PDELAYREQTX => gem1_ptp_tx_o.pdelay_req,
      EMIOGEM1PDELAYRESPRX => gem1_ptp_rx_o.pdelay_resp,
      EMIOGEM1PDELAYRESPTX => gem1_ptp_tx_o.pdelay_resp,
      EMIOGEM1RXSOF => open,
      EMIOGEM1SYNCFRAMERX => gem1_ptp_rx_o.sync,
      EMIOGEM1SYNCFRAMETX => gem1_ptp_tx_o.sync,
      EMIOGEM1TSUTIMERCMPVAL => gem1_tsu_timer_cmp_val_o,
      EMIOGEM1TXRFIXEDLAT => open,
      EMIOGEM1TXSOF => open,
      EMIOGEM2DELAYREQRX => gem2_ptp_rx_o.delay_req,
      EMIOGEM2DELAYREQTX => gem2_ptp_tx_o.delay_req,
      EMIOGEM2PDELAYREQRX => gem2_ptp_rx_o.pdelay_req,
      EMIOGEM2PDELAYREQTX => gem2_ptp_tx_o.pdelay_req,
      EMIOGEM2PDELAYRESPRX => gem2_ptp_rx_o.pdelay_resp,
      EMIOGEM2PDELAYRESPTX => gem2_ptp_tx_o.pdelay_resp,
      EMIOGEM2RXSOF => open,
      EMIOGEM2SYNCFRAMERX => gem2_ptp_rx_o.sync,
      EMIOGEM2SYNCFRAMETX => gem2_ptp_tx_o.sync,
      EMIOGEM2TSUTIMERCMPVAL => gem2_tsu_timer_cmp_val_o,
      EMIOGEM2TXRFIXEDLAT => open,
      EMIOGEM2TXSOF => open,
      EMIOGEM3DELAYREQRX => gem3_ptp_rx_o.delay_req,
      EMIOGEM3DELAYREQTX => gem3_ptp_tx_o.delay_req,
      EMIOGEM3PDELAYREQRX => gem3_ptp_rx_o.pdelay_req,
      EMIOGEM3PDELAYREQTX => gem3_ptp_tx_o.pdelay_req,
      EMIOGEM3PDELAYRESPRX => gem3_ptp_rx_o.pdelay_resp,
      EMIOGEM3PDELAYRESPTX => gem3_ptp_tx_o.pdelay_resp,
      EMIOGEM3RXSOF => open,
      EMIOGEM3SYNCFRAMERX => gem3_ptp_rx_o.sync,
      EMIOGEM3SYNCFRAMETX => gem3_ptp_tx_o.sync,
      EMIOGEM3TSUTIMERCMPVAL => gem3_tsu_timer_cmp_val_o,
      EMIOGEM3TXRFIXEDLAT => open,
      EMIOGEM3TXSOF => open,
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
      EMIOSDIO0BUSPOWER => open,
      EMIOSDIO0BUSVOLT => open,
      EMIOSDIO0CLKOUT => open,
      EMIOSDIO0CMDENA => open,
      EMIOSDIO0CMDOUT => open,
      EMIOSDIO0DATAENA => open,
      EMIOSDIO0DATAOUT => open,
      EMIOSDIO0LEDCONTROL => open,
      EMIOSDIO1BUSPOWER => open,
      EMIOSDIO1BUSVOLT => open,
      EMIOSDIO1CLKOUT => open,
      EMIOSDIO1CMDENA => open,
      EMIOSDIO1CMDOUT => open,
      EMIOSDIO1DATAENA => open,
      EMIOSDIO1DATAOUT => open,
      EMIOSDIO1LEDCONTROL => open,
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
      EMIOTTC0WAVEO => open,
      EMIOTTC1WAVEO => open,
      EMIOTTC2WAVEO => open,
      EMIOTTC3WAVEO => open,
      EMIOU2DSPORTVBUSCTRLUSB30 => open,
      EMIOU2DSPORTVBUSCTRLUSB31 => open,
      EMIOU3DSPORTVBUSCTRLUSB30 => open,
      EMIOU3DSPORTVBUSCTRLUSB31 => open,
      EMIOUART0DTRN => uart0_dtrn_s,
      EMIOUART0RTSN => uart0_rtsn_s,
      EMIOUART0TX => uart0_o.data,
      EMIOUART1DTRN => uart1_dtrn_s,
      EMIOUART1RTSN => uart1_rtsn_s,
      EMIOUART1TX => uart1_o.data,
      EMIOWDT0RSTO => open,
      EMIOWDT1RSTO => open,
      FMIOGEM0FIFORXCLKTOPLBUFG => open,
      FMIOGEM0FIFOTXCLKTOPLBUFG => open,
      FMIOGEM1FIFORXCLKTOPLBUFG => open,
      FMIOGEM1FIFOTXCLKTOPLBUFG => open,
      FMIOGEM2FIFORXCLKTOPLBUFG => open,
      FMIOGEM2FIFOTXCLKTOPLBUFG => open,
      FMIOGEM3FIFORXCLKTOPLBUFG => open,
      FMIOGEM3FIFOTXCLKTOPLBUFG => open,
      FMIOGEMTSUCLKTOPLBUFG => gem_tsu_ps_clock_s,
      FTMGPO => open,
      GDMA2PLCACK => gdma_cack_s,
      GDMA2PLTVLD => gdma_tvld_s,
      MAXIGP0ARADDR => m_fwd(0).ar.addr(39 downto 0),
      MAXIGP0ARBURST => m_fwd(0).ar.burst,
      MAXIGP0ARCACHE => m_fwd(0).ar.cache,
      MAXIGP0ARID => m_fwd(0).ar.id,
      MAXIGP0ARLEN => m_fwd(0).ar.len,
      MAXIGP0ARLOCK => m_fwd(0).ar.lock,
      MAXIGP0ARPROT => m_fwd(0).ar.prot,
      MAXIGP0ARQOS => m_fwd(0).ar.qos,
      MAXIGP0ARSIZE => m_fwd(0).ar.size,
      MAXIGP0ARUSER => open,
      MAXIGP0ARVALID => m_fwd(0).ar.valid,
      MAXIGP0AWADDR => m_fwd(0).aw.addr(39 downto 0),
      MAXIGP0AWBURST => m_fwd(0).aw.burst,
      MAXIGP0AWCACHE => m_fwd(0).aw.cache,
      MAXIGP0AWID => m_fwd(0).aw.id,
      MAXIGP0AWLEN => m_fwd(0).aw.len,
      MAXIGP0AWLOCK => m_fwd(0).aw.lock,
      MAXIGP0AWPROT => m_fwd(0).aw.prot,
      MAXIGP0AWQOS => m_fwd(0).aw.qos,
      MAXIGP0AWSIZE => m_fwd(0).aw.size,
      MAXIGP0AWUSER => open,
      MAXIGP0AWVALID => m_fwd(0).aw.valid,
      MAXIGP0BREADY => m_fwd(0).bready,
      MAXIGP0RREADY => m_fwd(0).rready,
      MAXIGP0WDATA => m_fwd(0).wdata,
      MAXIGP0WLAST => m_fwd(0).wlast,
      MAXIGP0WSTRB => m_fwd(0).wstrb,
      MAXIGP0WVALID => m_fwd(0).wvalid,
      MAXIGP1ARADDR => m_fwd(1).ar.addr(39 downto 0),
      MAXIGP1ARBURST => m_fwd(1).ar.burst,
      MAXIGP1ARCACHE => m_fwd(1).ar.cache,
      MAXIGP1ARID => m_fwd(1).ar.id,
      MAXIGP1ARLEN => m_fwd(1).ar.len,
      MAXIGP1ARLOCK => m_fwd(1).ar.lock,
      MAXIGP1ARPROT => m_fwd(1).ar.prot,
      MAXIGP1ARQOS => m_fwd(1).ar.qos,
      MAXIGP1ARSIZE => m_fwd(1).ar.size,
      MAXIGP1ARUSER => open,
      MAXIGP1ARVALID => m_fwd(1).ar.valid,
      MAXIGP1AWADDR => m_fwd(1).aw.addr(39 downto 0),
      MAXIGP1AWBURST => m_fwd(1).aw.burst,
      MAXIGP1AWCACHE => m_fwd(1).aw.cache,
      MAXIGP1AWID => m_fwd(1).aw.id,
      MAXIGP1AWLEN => m_fwd(1).aw.len,
      MAXIGP1AWLOCK => m_fwd(1).aw.lock,
      MAXIGP1AWPROT => m_fwd(1).aw.prot,
      MAXIGP1AWQOS => m_fwd(1).aw.qos,
      MAXIGP1AWSIZE => m_fwd(1).aw.size,
      MAXIGP1AWUSER => open,
      MAXIGP1AWVALID => m_fwd(1).aw.valid,
      MAXIGP1BREADY => m_fwd(1).bready,
      MAXIGP1RREADY => m_fwd(1).rready,
      MAXIGP1WDATA => m_fwd(1).wdata,
      MAXIGP1WLAST => m_fwd(1).wlast,
      MAXIGP1WSTRB => m_fwd(1).wstrb,
      MAXIGP1WVALID => m_fwd(1).wvalid,
      MAXIGP2ARADDR => m_fwd(2).ar.addr(39 downto 0),
      MAXIGP2ARBURST => m_fwd(2).ar.burst,
      MAXIGP2ARCACHE => m_fwd(2).ar.cache,
      MAXIGP2ARID => m_fwd(2).ar.id,
      MAXIGP2ARLEN => m_fwd(2).ar.len,
      MAXIGP2ARLOCK => m_fwd(2).ar.lock,
      MAXIGP2ARPROT => m_fwd(2).ar.prot,
      MAXIGP2ARQOS => m_fwd(2).ar.qos,
      MAXIGP2ARSIZE => m_fwd(2).ar.size,
      MAXIGP2ARUSER => open,
      MAXIGP2ARVALID => m_fwd(2).ar.valid,
      MAXIGP2AWADDR => m_fwd(2).aw.addr(39 downto 0),
      MAXIGP2AWBURST => m_fwd(2).aw.burst,
      MAXIGP2AWCACHE => m_fwd(2).aw.cache,
      MAXIGP2AWID => m_fwd(2).aw.id,
      MAXIGP2AWLEN => m_fwd(2).aw.len,
      MAXIGP2AWLOCK => m_fwd(2).aw.lock,
      MAXIGP2AWPROT => m_fwd(2).aw.prot,
      MAXIGP2AWQOS => m_fwd(2).aw.qos,
      MAXIGP2AWSIZE => m_fwd(2).aw.size,
      MAXIGP2AWUSER => open,
      MAXIGP2AWVALID => m_fwd(2).aw.valid,
      MAXIGP2BREADY => m_fwd(2).bready,
      MAXIGP2RREADY => m_fwd(2).rready,
      MAXIGP2WDATA => m_fwd(2).wdata,
      MAXIGP2WLAST => m_fwd(2).wlast,
      MAXIGP2WSTRB => m_fwd(2).wstrb,
      MAXIGP2WVALID => m_fwd(2).wvalid,
      OSCRTCCLK => open,
      PLCLK => pl_clock_s,
      PMUAIBAFIFMFPDREQ => open,
      PMUAIBAFIFMLPDREQ => open,
      PMUERRORTOPL => open,
      PMUPLGPO => open,
      PSPLEVENTO => open,
      PSPLIRQFPD => ps_pl_irq_fpd_s,
      PSPLIRQLPD => ps_pl_irq_lpd_s,
      PSPLSTANDBYWFE => open,
      PSPLSTANDBYWFI => open,
      PSPLTRACECTL => open,
      PSPLTRACEDATA => open,
      PSPLTRIGACK => open,
      PSPLTRIGGER => open,
      RPUEVENTO0 => open,
      RPUEVENTO1 => open,
      SACEFPDACADDR => open,
      SACEFPDACPROT => open,
      SACEFPDACSNOOP => open,
      SACEFPDACVALID => open,
      SACEFPDARREADY => open,
      SACEFPDAWREADY => open,
      SACEFPDBID => open,
      SACEFPDBRESP => open,
      SACEFPDBUSER => open,
      SACEFPDBVALID => open,
      SACEFPDCDREADY => open,
      SACEFPDCRREADY => open,
      SACEFPDRDATA => open,
      SACEFPDRID => open,
      SACEFPDRLAST => open,
      SACEFPDRRESP => open,
      SACEFPDRUSER => open,
      SACEFPDRVALID => open,
      SACEFPDWREADY => open,
      SAXIACPARREADY => s_bwd(7).arready,
      SAXIACPAWREADY => s_bwd(7).awready,
      SAXIACPBID => s_bwd(7).bid(4 downto 0),
      SAXIACPBRESP => s_bwd(7).bresp,
      SAXIACPBVALID => s_bwd(7).bvalid,
      SAXIACPRDATA => s_bwd(7).rdata,
      SAXIACPRID => s_bwd(7).rid(4 downto 0),
      SAXIACPRLAST => s_bwd(7).rlast,
      SAXIACPRRESP => s_bwd(7).rresp,
      SAXIACPRVALID => s_bwd(7).rvalid,
      SAXIACPWREADY => s_bwd(7).wready,
      SAXIGP0ARREADY => s_bwd(0).arready,
      SAXIGP0AWREADY => s_bwd(0).awready,
      SAXIGP0BID => s_bwd(0).bid(5 downto 0),
      SAXIGP0BRESP => s_bwd(0).bresp,
      SAXIGP0BVALID => s_bwd(0).bvalid,
      SAXIGP0RACOUNT => afi_level(0).racount,
      SAXIGP0RCOUNT => afi_level(0).rcount,
      SAXIGP0RDATA => s_bwd(0).rdata,
      SAXIGP0RID => s_bwd(0).rid(5 downto 0),
      SAXIGP0RLAST => s_bwd(0).rlast,
      SAXIGP0RRESP => s_bwd(0).rresp,
      SAXIGP0RVALID => s_bwd(0).rvalid,
      SAXIGP0WACOUNT => afi_level(0).wacount,
      SAXIGP0WCOUNT => afi_level(0).wcount,
      SAXIGP0WREADY => s_bwd(0).wready,
      SAXIGP1ARREADY => s_bwd(1).arready,
      SAXIGP1AWREADY => s_bwd(1).awready,
      SAXIGP1BID => s_bwd(1).bid(5 downto 0),
      SAXIGP1BRESP => s_bwd(1).bresp,
      SAXIGP1BVALID => s_bwd(1).bvalid,
      SAXIGP1RACOUNT => afi_level(1).racount,
      SAXIGP1RCOUNT => afi_level(1).rcount,
      SAXIGP1RDATA => s_bwd(1).rdata,
      SAXIGP1RID => s_bwd(1).rid(5 downto 0),
      SAXIGP1RLAST => s_bwd(1).rlast,
      SAXIGP1RRESP => s_bwd(1).rresp,
      SAXIGP1RVALID => s_bwd(1).rvalid,
      SAXIGP1WACOUNT => afi_level(1).wacount,
      SAXIGP1WCOUNT => afi_level(1).wcount,
      SAXIGP1WREADY => s_bwd(1).wready,
      SAXIGP2ARREADY => s_bwd(2).arready,
      SAXIGP2AWREADY => s_bwd(2).awready,
      SAXIGP2BID => s_bwd(2).bid(5 downto 0),
      SAXIGP2BRESP => s_bwd(2).bresp,
      SAXIGP2BVALID => s_bwd(2).bvalid,
      SAXIGP2RACOUNT => afi_level(2).racount,
      SAXIGP2RCOUNT => afi_level(2).rcount,
      SAXIGP2RDATA => s_bwd(2).rdata,
      SAXIGP2RID => s_bwd(2).rid(5 downto 0),
      SAXIGP2RLAST => s_bwd(2).rlast,
      SAXIGP2RRESP => s_bwd(2).rresp,
      SAXIGP2RVALID => s_bwd(2).rvalid,
      SAXIGP2WACOUNT => afi_level(2).wacount,
      SAXIGP2WCOUNT => afi_level(2).wcount,
      SAXIGP2WREADY => s_bwd(2).wready,
      SAXIGP3ARREADY => s_bwd(3).arready,
      SAXIGP3AWREADY => s_bwd(3).awready,
      SAXIGP3BID => s_bwd(3).bid(5 downto 0),
      SAXIGP3BRESP => s_bwd(3).bresp,
      SAXIGP3BVALID => s_bwd(3).bvalid,
      SAXIGP3RACOUNT => afi_level(3).racount,
      SAXIGP3RCOUNT => afi_level(3).rcount,
      SAXIGP3RDATA => s_bwd(3).rdata,
      SAXIGP3RID => s_bwd(3).rid(5 downto 0),
      SAXIGP3RLAST => s_bwd(3).rlast,
      SAXIGP3RRESP => s_bwd(3).rresp,
      SAXIGP3RVALID => s_bwd(3).rvalid,
      SAXIGP3WACOUNT => afi_level(3).wacount,
      SAXIGP3WCOUNT => afi_level(3).wcount,
      SAXIGP3WREADY => s_bwd(3).wready,
      SAXIGP4ARREADY => s_bwd(4).arready,
      SAXIGP4AWREADY => s_bwd(4).awready,
      SAXIGP4BID => s_bwd(4).bid(5 downto 0),
      SAXIGP4BRESP => s_bwd(4).bresp,
      SAXIGP4BVALID => s_bwd(4).bvalid,
      SAXIGP4RACOUNT => afi_level(4).racount,
      SAXIGP4RCOUNT => afi_level(4).rcount,
      SAXIGP4RDATA => s_bwd(4).rdata,
      SAXIGP4RID => s_bwd(4).rid(5 downto 0),
      SAXIGP4RLAST => s_bwd(4).rlast,
      SAXIGP4RRESP => s_bwd(4).rresp,
      SAXIGP4RVALID => s_bwd(4).rvalid,
      SAXIGP4WACOUNT => afi_level(4).wacount,
      SAXIGP4WCOUNT => afi_level(4).wcount,
      SAXIGP4WREADY => s_bwd(4).wready,
      SAXIGP5ARREADY => s_bwd(5).arready,
      SAXIGP5AWREADY => s_bwd(5).awready,
      SAXIGP5BID => s_bwd(5).bid(5 downto 0),
      SAXIGP5BRESP => s_bwd(5).bresp,
      SAXIGP5BVALID => s_bwd(5).bvalid,
      SAXIGP5RACOUNT => afi_level(5).racount,
      SAXIGP5RCOUNT => afi_level(5).rcount,
      SAXIGP5RDATA => s_bwd(5).rdata,
      SAXIGP5RID => s_bwd(5).rid(5 downto 0),
      SAXIGP5RLAST => s_bwd(5).rlast,
      SAXIGP5RRESP => s_bwd(5).rresp,
      SAXIGP5RVALID => s_bwd(5).rvalid,
      SAXIGP5WACOUNT => afi_level(5).wacount,
      SAXIGP5WCOUNT => afi_level(5).wcount,
      SAXIGP5WREADY => s_bwd(5).wready,
      SAXIGP6ARREADY => s_bwd(6).arready,
      SAXIGP6AWREADY => s_bwd(6).awready,
      SAXIGP6BID => s_bwd(6).bid(5 downto 0),
      SAXIGP6BRESP => s_bwd(6).bresp,
      SAXIGP6BVALID => s_bwd(6).bvalid,
      SAXIGP6RACOUNT => afi_level(6).racount,
      SAXIGP6RCOUNT => afi_level(6).rcount,
      SAXIGP6RDATA => s_bwd(6).rdata,
      SAXIGP6RID => s_bwd(6).rid(5 downto 0),
      SAXIGP6RLAST => s_bwd(6).rlast,
      SAXIGP6RRESP => s_bwd(6).rresp,
      SAXIGP6RVALID => s_bwd(6).rvalid,
      SAXIGP6WACOUNT => afi_level(6).wacount,
      SAXIGP6WCOUNT => afi_level(6).wcount,
      SAXIGP6WREADY => s_bwd(6).wready,
      ADMAFCICLK => adma_clock_s,
      AIBPMUAFIFMFPDACK => '0',
      AIBPMUAFIFMLPDACK => '0',
      DDRCEXTREFRESHRANK0REQ => '0',
      DDRCEXTREFRESHRANK1REQ => '0',
      DDRCREFRESHPLCLK => '0',
      DPAUXDATAIN => '0',
      DPEXTERNALCUSTOMEVENT1 => '0',
      DPEXTERNALCUSTOMEVENT2 => '0',
      DPEXTERNALVSYNCEVENT => '0',
      DPHOTPLUGDETECT => '0',
      DPLIVEGFXALPHAIN => (others => '0'),
      DPLIVEGFXPIXEL1IN => (others => '0'),
      DPLIVEVIDEOINDE => '0',
      DPLIVEVIDEOINHSYNC => '0',
      DPLIVEVIDEOINPIXEL1 => (others => '0'),
      DPLIVEVIDEOINVSYNC => '0',
      DPMAXISMIXEDAUDIOTREADY => '0',
      DPSAXISAUDIOCLK => '0',
      DPSAXISAUDIOTDATA => (others => '0'),
      DPSAXISAUDIOTID => '0',
      DPSAXISAUDIOTVALID => '0',
      DPVIDEOINCLK => '0',
      EMIOCAN0PHYRX => '0',
      EMIOCAN1PHYRX => '0',
      EMIOENET0DMATXSTATUSTOG => '0',
      EMIOENET0EXTINTIN => gem0_ext_int_i,
      EMIOENET0GMIICOL => gem0_gmii_col_i,
      EMIOENET0GMIICRS => gem0_gmii_crs_i,
      EMIOENET0GMIIRXCLK => gem0_gmii_rx_clock_i,
      EMIOENET0GMIIRXD => gem_gmii_rxd_s(0),
      EMIOENET0GMIIRXDV => gem0_gmii_rx_i.en,
      EMIOENET0GMIIRXER => gem0_gmii_rx_i.er,
      EMIOENET0GMIITXCLK => gem0_tx_clock_i,
      EMIOENET0MDIOI => gem0_smi_i.mdio,
      EMIOENET0RXWOVERFLOW => '0',
      EMIOENET0TXRCONTROL => '0',
      EMIOENET0TXRDATA => (others => '0'),
      EMIOENET0TXRDATARDY => '0',
      EMIOENET0TXREOP => '1',
      EMIOENET0TXRERR => '0',
      EMIOENET0TXRFLUSHED => '0',
      EMIOENET0TXRSOP => '1',
      EMIOENET0TXRUNDERFLOW => '0',
      EMIOENET0TXRVALID => '0',
      EMIOENET1DMATXSTATUSTOG => '0',
      EMIOENET1EXTINTIN => gem1_ext_int_i,
      EMIOENET1GMIICOL => gem1_gmii_col_i,
      EMIOENET1GMIICRS => gem1_gmii_crs_i,
      EMIOENET1GMIIRXCLK => gem1_gmii_rx_clock_i,
      EMIOENET1GMIIRXD => gem_gmii_rxd_s(1),
      EMIOENET1GMIIRXDV => gem1_gmii_rx_i.en,
      EMIOENET1GMIIRXER => gem1_gmii_rx_i.er,
      EMIOENET1GMIITXCLK => gem1_tx_clock_i,
      EMIOENET1MDIOI => gem1_smi_i.mdio,
      EMIOENET1RXWOVERFLOW => '0',
      EMIOENET1TXRCONTROL => '0',
      EMIOENET1TXRDATA => (others => '0'),
      EMIOENET1TXRDATARDY => '0',
      EMIOENET1TXREOP => '1',
      EMIOENET1TXRERR => '0',
      EMIOENET1TXRFLUSHED => '0',
      EMIOENET1TXRSOP => '1',
      EMIOENET1TXRUNDERFLOW => '0',
      EMIOENET1TXRVALID => '0',
      EMIOENET2DMATXSTATUSTOG => '0',
      EMIOENET2EXTINTIN => gem2_ext_int_i,
      EMIOENET2GMIICOL => gem2_gmii_col_i,
      EMIOENET2GMIICRS => gem2_gmii_crs_i,
      EMIOENET2GMIIRXCLK => gem2_gmii_rx_clock_i,
      EMIOENET2GMIIRXD => gem_gmii_rxd_s(2),
      EMIOENET2GMIIRXDV => gem2_gmii_rx_i.en,
      EMIOENET2GMIIRXER => gem2_gmii_rx_i.er,
      EMIOENET2GMIITXCLK => gem2_tx_clock_i,
      EMIOENET2MDIOI => gem2_smi_i.mdio,
      EMIOENET2RXWOVERFLOW => '0',
      EMIOENET2TXRCONTROL => '0',
      EMIOENET2TXRDATA => (others => '0'),
      EMIOENET2TXRDATARDY => '0',
      EMIOENET2TXREOP => '1',
      EMIOENET2TXRERR => '0',
      EMIOENET2TXRFLUSHED => '0',
      EMIOENET2TXRSOP => '1',
      EMIOENET2TXRUNDERFLOW => '0',
      EMIOENET2TXRVALID => '0',
      EMIOENET3DMATXSTATUSTOG => '0',
      EMIOENET3EXTINTIN => gem3_ext_int_i,
      EMIOENET3GMIICOL => gem3_gmii_col_i,
      EMIOENET3GMIICRS => gem3_gmii_crs_i,
      EMIOENET3GMIIRXCLK => gem3_gmii_rx_clock_i,
      EMIOENET3GMIIRXD => gem_gmii_rxd_s(3),
      EMIOENET3GMIIRXDV => gem3_gmii_rx_i.en,
      EMIOENET3GMIIRXER => gem3_gmii_rx_i.er,
      EMIOENET3GMIITXCLK => gem3_tx_clock_i,
      EMIOENET3MDIOI => gem3_smi_i.mdio,
      EMIOENET3RXWOVERFLOW => '0',
      EMIOENET3TXRCONTROL => '0',
      EMIOENET3TXRDATA => (others => '0'),
      EMIOENET3TXRDATARDY => '0',
      EMIOENET3TXREOP => '1',
      EMIOENET3TXRERR => '0',
      EMIOENET3TXRFLUSHED => '0',
      EMIOENET3TXRSOP => '1',
      EMIOENET3TXRUNDERFLOW => '0',
      EMIOENET3TXRVALID => '0',
      EMIOENETTSUCLK => gem_tsu_clock_i,
      EMIOGEM0TSUINCCTRL => gem_tsu_inc_ctrl_s(0),
      EMIOGEM1TSUINCCTRL => gem_tsu_inc_ctrl_s(1),
      EMIOGEM2TSUINCCTRL => gem_tsu_inc_ctrl_s(2),
      EMIOGEM3TSUINCCTRL => gem_tsu_inc_ctrl_s(3),
      EMIOGPIOI => gpio_i_s,
      EMIOHUBPORTOVERCRNTUSB20 => '0',
      EMIOHUBPORTOVERCRNTUSB21 => '0',
      EMIOHUBPORTOVERCRNTUSB30 => '0',
      EMIOHUBPORTOVERCRNTUSB31 => '0',
      EMIOI2C0SCLI => i2c0_i.scl,
      EMIOI2C0SDAI => i2c0_i.sda,
      EMIOI2C1SCLI => i2c1_i.scl,
      EMIOI2C1SDAI => i2c1_i.sda,
      EMIOSDIO0CDN => '0',
      EMIOSDIO0CMDIN => '0',
      EMIOSDIO0DATAIN => (others => '0'),
      EMIOSDIO0FBCLKIN => '0',
      EMIOSDIO0WP => '1',
      EMIOSDIO1CDN => '0',
      EMIOSDIO1CMDIN => '0',
      EMIOSDIO1DATAIN => (others => '0'),
      EMIOSDIO1FBCLKIN => '0',
      EMIOSDIO1WP => '1',
      EMIOSPI0MI => spi0_mi_s,
      EMIOSPI0SCLKI => '0',
      EMIOSPI0SI => '0',
      EMIOSPI0SSIN => '1',
      EMIOSPI1MI => spi1_mi_s,
      EMIOSPI1SCLKI => '0',
      EMIOSPI1SI => '0',
      EMIOSPI1SSIN => '1',
      EMIOTTC0CLKI => (others => '0'),
      EMIOTTC1CLKI => (others => '0'),
      EMIOTTC2CLKI => (others => '0'),
      EMIOTTC3CLKI => (others => '0'),
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
      EMIOWDT0CLKI => '0',
      EMIOWDT1CLKI => '0',
      FMIOGEM0FIFORXCLKFROMPL => '0',
      FMIOGEM0FIFOTXCLKFROMPL => '0',
      FMIOGEM0SIGNALDETECT => '0',
      FMIOGEM1FIFORXCLKFROMPL => '0',
      FMIOGEM1FIFOTXCLKFROMPL => '0',
      FMIOGEM1SIGNALDETECT => '0',
      FMIOGEM2FIFORXCLKFROMPL => '0',
      FMIOGEM2FIFOTXCLKFROMPL => '0',
      FMIOGEM2SIGNALDETECT => '0',
      FMIOGEM3FIFORXCLKFROMPL => '0',
      FMIOGEM3FIFOTXCLKFROMPL => '0',
      FMIOGEM3SIGNALDETECT => '0',
      FMIOGEMTSUCLKFROMPL => gem_tsu_ps_clock_i,
      FTMGPI => (others => '0'),
      GDMAFCICLK => gdma_clock_s,
      MAXIGP0ACLK => m_aclk(0),
      MAXIGP0ARREADY => m_bwd(0).arready,
      MAXIGP0AWREADY => m_bwd(0).awready,
      MAXIGP0BID => m_bwd(0).bid,
      MAXIGP0BRESP => m_bwd(0).bresp,
      MAXIGP0BVALID => m_bwd(0).bvalid,
      MAXIGP0RDATA => m_bwd(0).rdata,
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
      MAXIGP1RDATA => m_bwd(1).rdata,
      MAXIGP1RID => m_bwd(1).rid,
      MAXIGP1RLAST => m_bwd(1).rlast,
      MAXIGP1RRESP => m_bwd(1).rresp,
      MAXIGP1RVALID => m_bwd(1).rvalid,
      MAXIGP1WREADY => m_bwd(1).wready,
      MAXIGP2ACLK => m_aclk(2),
      MAXIGP2ARREADY => m_bwd(2).arready,
      MAXIGP2AWREADY => m_bwd(2).awready,
      MAXIGP2BID => m_bwd(2).bid,
      MAXIGP2BRESP => m_bwd(2).bresp,
      MAXIGP2BVALID => m_bwd(2).bvalid,
      MAXIGP2RDATA => m_bwd(2).rdata,
      MAXIGP2RID => m_bwd(2).rid,
      MAXIGP2RLAST => m_bwd(2).rlast,
      MAXIGP2RRESP => m_bwd(2).rresp,
      MAXIGP2RVALID => m_bwd(2).rvalid,
      MAXIGP2WREADY => m_bwd(2).wready,
      NFIQ0LPDRPU => '1',
      NFIQ1LPDRPU => '1',
      NIRQ0LPDRPU => '1',
      NIRQ1LPDRPU => '1',
      PL2ADMACVLD => adma_cvld_s,
      PL2ADMATACK => adma_tack_s,
      PL2GDMACVLD => gdma_cvld_s,
      PL2GDMATACK => gdma_tack_s,
      PLACECLK => '0',
      PLACPINACT => '0',
      PLFPGASTOP => (others => '0'),
      PLLAUXREFCLKFPD => (others => '0'),
      PLLAUXREFCLKLPD => (others => '0'),
      PLPMUGPI => (others => '0'),
      PLPSAPUGICFIQ => (others => '0'),
      PLPSAPUGICIRQ => (others => '0'),
      PLPSEVENTI => '0',
      PLPSIRQ0 => pl_ps_irq0_s,
      PLPSIRQ1 => pl_ps_irq1_s,
      PLPSTRACECLK => '0',
      PLPSTRIGACK => (others => '0'),
      PLPSTRIGGER => (others => '0'),
      PMUERRORFROMPL => (others => '0'),
      RPUEVENTI0 => '0',
      RPUEVENTI1 => '0',
      SACEFPDACREADY => '0',
      SACEFPDARADDR => (others => '0'),
      SACEFPDARBAR => (others => '0'),
      SACEFPDARBURST => (others => '0'),
      SACEFPDARCACHE => (others => '0'),
      SACEFPDARDOMAIN => (others => '0'),
      SACEFPDARID => (others => '0'),
      SACEFPDARLEN => (others => '0'),
      SACEFPDARLOCK => '0',
      SACEFPDARPROT => (others => '0'),
      SACEFPDARQOS => (others => '0'),
      SACEFPDARREGION => (others => '0'),
      SACEFPDARSIZE => (others => '0'),
      SACEFPDARSNOOP => (others => '0'),
      SACEFPDARUSER => "0000001111000000",
      SACEFPDARVALID => '0',
      SACEFPDAWADDR => (others => '0'),
      SACEFPDAWBAR => (others => '0'),
      SACEFPDAWBURST => (others => '0'),
      SACEFPDAWCACHE => (others => '0'),
      SACEFPDAWDOMAIN => (others => '0'),
      SACEFPDAWID => (others => '0'),
      SACEFPDAWLEN => (others => '0'),
      SACEFPDAWLOCK => '0',
      SACEFPDAWPROT => (others => '0'),
      SACEFPDAWQOS => (others => '0'),
      SACEFPDAWREGION => (others => '0'),
      SACEFPDAWSIZE => (others => '0'),
      SACEFPDAWSNOOP => (others => '0'),
      SACEFPDAWUSER => "0000001111000000",
      SACEFPDAWVALID => '0',
      SACEFPDBREADY => '0',
      SACEFPDCDDATA => (others => '0'),
      SACEFPDCDLAST => '0',
      SACEFPDCDVALID => '0',
      SACEFPDCRRESP => (others => '0'),
      SACEFPDCRVALID => '0',
      SACEFPDRACK => '0',
      SACEFPDRREADY => '0',
      SACEFPDWACK => '0',
      SACEFPDWDATA => (others => '0'),
      SACEFPDWLAST => '0',
      SACEFPDWSTRB => (others => '0'),
      SACEFPDWUSER => '0',
      SACEFPDWVALID => '0',
      SAXIACPACLK => s_aclk(7),
      SAXIACPARADDR => s_fwd(7).ar.addr(39 downto 0),
      SAXIACPARBURST => s_fwd(7).ar.burst,
      SAXIACPARCACHE => s_fwd(7).ar.cache,
      SAXIACPARID => s_fwd(7).ar.id(4 downto 0),
      SAXIACPARLEN => s_fwd(7).ar.len,
      SAXIACPARLOCK => s_fwd(7).ar.lock,
      SAXIACPARPROT => s_fwd(7).ar.prot,
      SAXIACPARQOS => s_fwd(7).ar.qos,
      SAXIACPARSIZE => s_fwd(7).ar.size,
      SAXIACPARUSER => s_fwd(7).ar.user,
      SAXIACPARVALID => s_fwd(7).ar.valid,
      SAXIACPAWADDR => s_fwd(7).aw.addr(39 downto 0),
      SAXIACPAWBURST => s_fwd(7).aw.burst,
      SAXIACPAWCACHE => s_fwd(7).aw.cache,
      SAXIACPAWID => s_fwd(7).aw.id(4 downto 0),
      SAXIACPAWLEN => s_fwd(7).aw.len,
      SAXIACPAWLOCK => s_fwd(7).aw.lock,
      SAXIACPAWPROT => s_fwd(7).aw.prot,
      SAXIACPAWQOS => s_fwd(7).aw.qos,
      SAXIACPAWSIZE => s_fwd(7).aw.size,
      SAXIACPAWUSER => s_fwd(7).aw.user,
      SAXIACPAWVALID => s_fwd(7).aw.valid,
      SAXIACPBREADY => s_fwd(7).bready,
      SAXIACPRREADY => s_fwd(7).rready,
      SAXIACPWDATA => s_fwd(7).wdata,
      SAXIACPWLAST => s_fwd(7).wlast,
      SAXIACPWSTRB => s_fwd(7).wstrb,
      SAXIACPWVALID => s_fwd(7).wvalid,
      SAXIGP0ARADDR => s_fwd(0).ar.addr,
      SAXIGP0ARBURST => s_fwd(0).ar.burst,
      SAXIGP0ARCACHE => s_fwd(0).ar.cache,
      SAXIGP0ARID => s_fwd(0).ar.id(5 downto 0),
      SAXIGP0ARLEN => s_fwd(0).ar.len,
      SAXIGP0ARLOCK => s_fwd(0).ar.lock,
      SAXIGP0ARPROT => s_fwd(0).ar.prot,
      SAXIGP0ARQOS => s_fwd(0).ar.qos,
      SAXIGP0ARSIZE => s_fwd(0).ar.size,
      SAXIGP0ARUSER => s_fwd(0).ar.user(0),
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
      SAXIGP0AWUSER => s_fwd(0).aw.user(0),
      SAXIGP0AWVALID => s_fwd(0).aw.valid,
      SAXIGP0BREADY => s_fwd(0).bready,
      SAXIGP0RCLK => s_aclk(0),
      SAXIGP0RREADY => s_fwd(0).rready,
      SAXIGP0WCLK => s_aclk(0),
      SAXIGP0WDATA => s_fwd(0).wdata,
      SAXIGP0WLAST => s_fwd(0).wlast,
      SAXIGP0WSTRB => s_fwd(0).wstrb,
      SAXIGP0WVALID => s_fwd(0).wvalid,
      SAXIGP1ARADDR => s_fwd(1).ar.addr,
      SAXIGP1ARBURST => s_fwd(1).ar.burst,
      SAXIGP1ARCACHE => s_fwd(1).ar.cache,
      SAXIGP1ARID => s_fwd(1).ar.id(5 downto 0),
      SAXIGP1ARLEN => s_fwd(1).ar.len,
      SAXIGP1ARLOCK => s_fwd(1).ar.lock,
      SAXIGP1ARPROT => s_fwd(1).ar.prot,
      SAXIGP1ARQOS => s_fwd(1).ar.qos,
      SAXIGP1ARSIZE => s_fwd(1).ar.size,
      SAXIGP1ARUSER => s_fwd(1).ar.user(0),
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
      SAXIGP1AWUSER => s_fwd(1).aw.user(0),
      SAXIGP1AWVALID => s_fwd(1).aw.valid,
      SAXIGP1BREADY => s_fwd(1).bready,
      SAXIGP1RCLK => s_aclk(1),
      SAXIGP1RREADY => s_fwd(1).rready,
      SAXIGP1WCLK => s_aclk(1),
      SAXIGP1WDATA => s_fwd(1).wdata,
      SAXIGP1WLAST => s_fwd(1).wlast,
      SAXIGP1WSTRB => s_fwd(1).wstrb,
      SAXIGP1WVALID => s_fwd(1).wvalid,
      SAXIGP2ARADDR => s_fwd(2).ar.addr,
      SAXIGP2ARBURST => s_fwd(2).ar.burst,
      SAXIGP2ARCACHE => s_fwd(2).ar.cache,
      SAXIGP2ARID => s_fwd(2).ar.id(5 downto 0),
      SAXIGP2ARLEN => s_fwd(2).ar.len,
      SAXIGP2ARLOCK => s_fwd(2).ar.lock,
      SAXIGP2ARPROT => s_fwd(2).ar.prot,
      SAXIGP2ARQOS => s_fwd(2).ar.qos,
      SAXIGP2ARSIZE => s_fwd(2).ar.size,
      SAXIGP2ARUSER => s_fwd(2).ar.user(0),
      SAXIGP2ARVALID => s_fwd(2).ar.valid,
      SAXIGP2AWADDR => s_fwd(2).aw.addr,
      SAXIGP2AWBURST => s_fwd(2).aw.burst,
      SAXIGP2AWCACHE => s_fwd(2).aw.cache,
      SAXIGP2AWID => s_fwd(2).aw.id(5 downto 0),
      SAXIGP2AWLEN => s_fwd(2).aw.len,
      SAXIGP2AWLOCK => s_fwd(2).aw.lock,
      SAXIGP2AWPROT => s_fwd(2).aw.prot,
      SAXIGP2AWQOS => s_fwd(2).aw.qos,
      SAXIGP2AWSIZE => s_fwd(2).aw.size,
      SAXIGP2AWUSER => s_fwd(2).aw.user(0),
      SAXIGP2AWVALID => s_fwd(2).aw.valid,
      SAXIGP2BREADY => s_fwd(2).bready,
      SAXIGP2RCLK => s_aclk(2),
      SAXIGP2RREADY => s_fwd(2).rready,
      SAXIGP2WCLK => s_aclk(2),
      SAXIGP2WDATA => s_fwd(2).wdata,
      SAXIGP2WLAST => s_fwd(2).wlast,
      SAXIGP2WSTRB => s_fwd(2).wstrb,
      SAXIGP2WVALID => s_fwd(2).wvalid,
      SAXIGP3ARADDR => s_fwd(3).ar.addr,
      SAXIGP3ARBURST => s_fwd(3).ar.burst,
      SAXIGP3ARCACHE => s_fwd(3).ar.cache,
      SAXIGP3ARID => s_fwd(3).ar.id(5 downto 0),
      SAXIGP3ARLEN => s_fwd(3).ar.len,
      SAXIGP3ARLOCK => s_fwd(3).ar.lock,
      SAXIGP3ARPROT => s_fwd(3).ar.prot,
      SAXIGP3ARQOS => s_fwd(3).ar.qos,
      SAXIGP3ARSIZE => s_fwd(3).ar.size,
      SAXIGP3ARUSER => s_fwd(3).ar.user(0),
      SAXIGP3ARVALID => s_fwd(3).ar.valid,
      SAXIGP3AWADDR => s_fwd(3).aw.addr,
      SAXIGP3AWBURST => s_fwd(3).aw.burst,
      SAXIGP3AWCACHE => s_fwd(3).aw.cache,
      SAXIGP3AWID => s_fwd(3).aw.id(5 downto 0),
      SAXIGP3AWLEN => s_fwd(3).aw.len,
      SAXIGP3AWLOCK => s_fwd(3).aw.lock,
      SAXIGP3AWPROT => s_fwd(3).aw.prot,
      SAXIGP3AWQOS => s_fwd(3).aw.qos,
      SAXIGP3AWSIZE => s_fwd(3).aw.size,
      SAXIGP3AWUSER => s_fwd(3).aw.user(0),
      SAXIGP3AWVALID => s_fwd(3).aw.valid,
      SAXIGP3BREADY => s_fwd(3).bready,
      SAXIGP3RCLK => s_aclk(3),
      SAXIGP3RREADY => s_fwd(3).rready,
      SAXIGP3WCLK => s_aclk(3),
      SAXIGP3WDATA => s_fwd(3).wdata,
      SAXIGP3WLAST => s_fwd(3).wlast,
      SAXIGP3WSTRB => s_fwd(3).wstrb,
      SAXIGP3WVALID => s_fwd(3).wvalid,
      SAXIGP4ARADDR => s_fwd(4).ar.addr,
      SAXIGP4ARBURST => s_fwd(4).ar.burst,
      SAXIGP4ARCACHE => s_fwd(4).ar.cache,
      SAXIGP4ARID => s_fwd(4).ar.id(5 downto 0),
      SAXIGP4ARLEN => s_fwd(4).ar.len,
      SAXIGP4ARLOCK => s_fwd(4).ar.lock,
      SAXIGP4ARPROT => s_fwd(4).ar.prot,
      SAXIGP4ARQOS => s_fwd(4).ar.qos,
      SAXIGP4ARSIZE => s_fwd(4).ar.size,
      SAXIGP4ARUSER => s_fwd(4).ar.user(0),
      SAXIGP4ARVALID => s_fwd(4).ar.valid,
      SAXIGP4AWADDR => s_fwd(4).aw.addr,
      SAXIGP4AWBURST => s_fwd(4).aw.burst,
      SAXIGP4AWCACHE => s_fwd(4).aw.cache,
      SAXIGP4AWID => s_fwd(4).aw.id(5 downto 0),
      SAXIGP4AWLEN => s_fwd(4).aw.len,
      SAXIGP4AWLOCK => s_fwd(4).aw.lock,
      SAXIGP4AWPROT => s_fwd(4).aw.prot,
      SAXIGP4AWQOS => s_fwd(4).aw.qos,
      SAXIGP4AWSIZE => s_fwd(4).aw.size,
      SAXIGP4AWUSER => s_fwd(4).aw.user(0),
      SAXIGP4AWVALID => s_fwd(4).aw.valid,
      SAXIGP4BREADY => s_fwd(4).bready,
      SAXIGP4RCLK => s_aclk(4),
      SAXIGP4RREADY => s_fwd(4).rready,
      SAXIGP4WCLK => s_aclk(4),
      SAXIGP4WDATA => s_fwd(4).wdata,
      SAXIGP4WLAST => s_fwd(4).wlast,
      SAXIGP4WSTRB => s_fwd(4).wstrb,
      SAXIGP4WVALID => s_fwd(4).wvalid,
      SAXIGP5ARADDR => s_fwd(5).ar.addr,
      SAXIGP5ARBURST => s_fwd(5).ar.burst,
      SAXIGP5ARCACHE => s_fwd(5).ar.cache,
      SAXIGP5ARID => s_fwd(5).ar.id(5 downto 0),
      SAXIGP5ARLEN => s_fwd(5).ar.len,
      SAXIGP5ARLOCK => s_fwd(5).ar.lock,
      SAXIGP5ARPROT => s_fwd(5).ar.prot,
      SAXIGP5ARQOS => s_fwd(5).ar.qos,
      SAXIGP5ARSIZE => s_fwd(5).ar.size,
      SAXIGP5ARUSER => s_fwd(5).ar.user(0),
      SAXIGP5ARVALID => s_fwd(5).ar.valid,
      SAXIGP5AWADDR => s_fwd(5).aw.addr,
      SAXIGP5AWBURST => s_fwd(5).aw.burst,
      SAXIGP5AWCACHE => s_fwd(5).aw.cache,
      SAXIGP5AWID => s_fwd(5).aw.id(5 downto 0),
      SAXIGP5AWLEN => s_fwd(5).aw.len,
      SAXIGP5AWLOCK => s_fwd(5).aw.lock,
      SAXIGP5AWPROT => s_fwd(5).aw.prot,
      SAXIGP5AWQOS => s_fwd(5).aw.qos,
      SAXIGP5AWSIZE => s_fwd(5).aw.size,
      SAXIGP5AWUSER => s_fwd(5).aw.user(0),
      SAXIGP5AWVALID => s_fwd(5).aw.valid,
      SAXIGP5BREADY => s_fwd(5).bready,
      SAXIGP5RCLK => s_aclk(5),
      SAXIGP5RREADY => s_fwd(5).rready,
      SAXIGP5WCLK => s_aclk(5),
      SAXIGP5WDATA => s_fwd(5).wdata,
      SAXIGP5WLAST => s_fwd(5).wlast,
      SAXIGP5WSTRB => s_fwd(5).wstrb,
      SAXIGP5WVALID => s_fwd(5).wvalid,
      SAXIGP6ARADDR => s_fwd(6).ar.addr,
      SAXIGP6ARBURST => s_fwd(6).ar.burst,
      SAXIGP6ARCACHE => s_fwd(6).ar.cache,
      SAXIGP6ARID => s_fwd(6).ar.id(5 downto 0),
      SAXIGP6ARLEN => s_fwd(6).ar.len,
      SAXIGP6ARLOCK => s_fwd(6).ar.lock,
      SAXIGP6ARPROT => s_fwd(6).ar.prot,
      SAXIGP6ARQOS => s_fwd(6).ar.qos,
      SAXIGP6ARSIZE => s_fwd(6).ar.size,
      SAXIGP6ARUSER => s_fwd(6).ar.user(0),
      SAXIGP6ARVALID => s_fwd(6).ar.valid,
      SAXIGP6AWADDR => s_fwd(6).aw.addr,
      SAXIGP6AWBURST => s_fwd(6).aw.burst,
      SAXIGP6AWCACHE => s_fwd(6).aw.cache,
      SAXIGP6AWID => s_fwd(6).aw.id(5 downto 0),
      SAXIGP6AWLEN => s_fwd(6).aw.len,
      SAXIGP6AWLOCK => s_fwd(6).aw.lock,
      SAXIGP6AWPROT => s_fwd(6).aw.prot,
      SAXIGP6AWQOS => s_fwd(6).aw.qos,
      SAXIGP6AWSIZE => s_fwd(6).aw.size,
      SAXIGP6AWUSER => s_fwd(6).aw.user(0),
      SAXIGP6AWVALID => s_fwd(6).aw.valid,
      SAXIGP6BREADY => s_fwd(6).bready,
      SAXIGP6RCLK => s_aclk(6),
      SAXIGP6RREADY => s_fwd(6).rready,
      SAXIGP6WCLK => s_aclk(6),
      SAXIGP6WDATA => s_fwd(6).wdata,
      SAXIGP6WLAST => s_fwd(6).wlast,
      SAXIGP6WSTRB => s_fwd(6).wstrb,
      SAXIGP6WVALID => s_fwd(6).wvalid,
      STMEVENT => (others => '0')
      );

  pl_clocks: for i in 0 to 3
  generate
    buf: BUFG_PS
      port map(
        I => pl_clock_s(i),
        O => pl_clock_o(i)
        );

    pl_reset_n_o(i) <= gpio_o_s(95 - i);
  end generate;

  gem_tsu_ps_clock_buf: BUFG_PS
    port map(
      I => gem_tsu_ps_clock_s,
      O => gem_tsu_ps_clock_o
      );

  irq: for i in 0 to 7
  generate
    pl_ps_irq0_s(i) <= pl_ps_irq_i(i);
    pl_ps_irq1_s(i) <= pl_ps_irq_i(8 + i);
  end generate;

  irq_lpd: for i in 0 to 99
  generate
    ps_pl_irq_lpd_o(i) <= ps_pl_irq_lpd_s(i);
  end generate;

  irq_fpd: for i in 0 to 63
  generate
    ps_pl_irq_fpd_o(i) <= ps_pl_irq_fpd_s(i);
  end generate;

  dma: for i in 0 to 7
  generate
    adma_clock_s(i) <= adma_clock_i(i);
    adma_cvld_s(i) <= adma_i(i).cvld;
    adma_tack_s(i) <= adma_i(i).tack;
    adma_o(i).cack <= adma_cack_s(i);
    adma_o(i).tvld <= adma_tvld_s(i);
    gdma_clock_s(i) <= gdma_clock_i(i);
    gdma_cvld_s(i) <= gdma_i(i).cvld;
    gdma_tack_s(i) <= gdma_i(i).tack;
    gdma_o(i).cack <= gdma_cack_s(i);
    gdma_o(i).tvld <= gdma_tvld_s(i);
  end generate;

  m_aclk <= (m_axi_hpm0_fpd_clock_i, m_axi_hpm1_fpd_clock_i, m_axi_hpm0_lpd_clock_i);
  m_axi_hpm0_fpd_o <= m_o(0);
  m_axi_hpm1_fpd_o <= m_o(1);
  m_axi_hpm0_lpd_o <= m_o(2);
  m_i <= (m_axi_hpm0_fpd_i, m_axi_hpm1_fpd_i, m_axi_hpm0_lpd_i);

  s_aclk <= (s_axi_hpc0_fpd_clock_i, s_axi_hpc1_fpd_clock_i,
             s_axi_hp0_fpd_clock_i, s_axi_hp1_fpd_clock_i,
             s_axi_hp2_fpd_clock_i, s_axi_hp3_fpd_clock_i,
             s_axi_lpd_clock_i, s_axi_acp_fpd_clock_i);
  s_axi_hpc0_fpd_o <= s_o(0);
  s_axi_hpc1_fpd_o <= s_o(1);
  s_axi_hp0_fpd_o <= s_o(2);
  s_axi_hp1_fpd_o <= s_o(3);
  s_axi_hp2_fpd_o <= s_o(4);
  s_axi_hp3_fpd_o <= s_o(5);
  s_axi_lpd_o <= s_o(6);
  s_axi_acp_fpd_o <= s_o(7);
  s_i <= (s_axi_hpc0_fpd_i, s_axi_hpc1_fpd_i,
          s_axi_hp0_fpd_i, s_axi_hp1_fpd_i,
          s_axi_hp2_fpd_i, s_axi_hp3_fpd_i,
          s_axi_lpd_i, s_axi_acp_fpd_i);

  s_axi_hpc0_fpd_level_o <= (read_data => unsigned(afi_level(0).rcount),
                             write_data => unsigned(afi_level(0).wcount),
                             read_command => unsigned(afi_level(0).racount),
                             write_command => unsigned(afi_level(0).wacount));
  s_axi_hpc1_fpd_level_o <= (read_data => unsigned(afi_level(1).rcount),
                             write_data => unsigned(afi_level(1).wcount),
                             read_command => unsigned(afi_level(1).racount),
                             write_command => unsigned(afi_level(1).wacount));
  s_axi_hp0_fpd_level_o <= (read_data => unsigned(afi_level(2).rcount),
                            write_data => unsigned(afi_level(2).wcount),
                            read_command => unsigned(afi_level(2).racount),
                            write_command => unsigned(afi_level(2).wacount));
  s_axi_hp1_fpd_level_o <= (read_data => unsigned(afi_level(3).rcount),
                            write_data => unsigned(afi_level(3).wcount),
                            read_command => unsigned(afi_level(3).racount),
                            write_command => unsigned(afi_level(3).wacount));
  s_axi_hp2_fpd_level_o <= (read_data => unsigned(afi_level(4).rcount),
                            write_data => unsigned(afi_level(4).wcount),
                            read_command => unsigned(afi_level(4).racount),
                            write_command => unsigned(afi_level(4).wacount));
  s_axi_hp3_fpd_level_o <= (read_data => unsigned(afi_level(5).rcount),
                            write_data => unsigned(afi_level(5).wcount),
                            read_command => unsigned(afi_level(5).racount),
                            write_command => unsigned(afi_level(5).wacount));
  s_axi_lpd_level_o <= (read_data => unsigned(afi_level(6).rcount),
                        write_data => unsigned(afi_level(6).wcount),
                        read_command => unsigned(afi_level(6).racount),
                        write_command => unsigned(afi_level(6).wacount));

  m_port: for i in m_config_c'range
  generate
    m_o(i) <= to_master(m_config_c(i), m_fwd(i));
    m_bwd(i) <= to_ps_bwd(m_config_c(i), m_i(i));
  end generate;

  s_port: for i in s_config_c'range
  generate
    s_fwd(i) <= to_ps_fwd(s_config_c(i), s_i(i));
    s_o(i) <= to_slave(s_config_c(i), s_bwd(i));
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

  gem0_gmii_tx_o.data <= std_ulogic_vector(gem_gmii_txd_s(0));
  gem1_gmii_tx_o.data <= std_ulogic_vector(gem_gmii_txd_s(1));
  gem2_gmii_tx_o.data <= std_ulogic_vector(gem_gmii_txd_s(2));
  gem3_gmii_tx_o.data <= std_ulogic_vector(gem_gmii_txd_s(3));
  gem_gmii_rxd_s <= (std_logic_vector(gem0_gmii_rx_i.data), std_logic_vector(gem1_gmii_rx_i.data),
                     std_logic_vector(gem2_gmii_rx_i.data), std_logic_vector(gem3_gmii_rx_i.data));
  gem_tsu_inc_ctrl_s <= (std_logic_vector(gem0_tsu_inc_ctrl_i), std_logic_vector(gem1_tsu_inc_ctrl_i),
                         std_logic_vector(gem2_tsu_inc_ctrl_i), std_logic_vector(gem3_tsu_inc_ctrl_i));
  gem_tsu_timer_o <= unsigned(gem_tsu_timer_s);

  uart0_o.rts <= not uart0_rtsn_s;
  uart0_o.dtr <= not uart0_dtrn_s;
  uart0_o.dcd <= '0';
  uart0_o.ri <= '0';
  uart0_ctsn_s <= not uart0_i.rts;
  uart0_dsrn_s <= not uart0_i.dtr;
  uart0_dcdn_s <= not uart0_i.dcd;
  uart0_rin_s <= not uart0_i.ri;

  uart1_o.rts <= not uart1_rtsn_s;
  uart1_o.dtr <= not uart1_dtrn_s;
  uart1_o.dcd <= '0';
  uart1_o.ri <= '0';
  uart1_ctsn_s <= not uart1_i.rts;
  uart1_dsrn_s <= not uart1_i.dtr;
  uart1_dcdn_s <= not uart1_i.dcd;
  uart1_rin_s <= not uart1_i.ri;

  i2c0_o.scl.drain_n <= not (i2c0_scl_tn_s and not i2c0_scl_o_s);
  i2c0_o.sda.drain_n <= not (i2c0_sda_tn_s and not i2c0_sda_o_s);
  i2c1_o.scl.drain_n <= not (i2c1_scl_tn_s and not i2c1_scl_o_s);
  i2c1_o.sda.drain_n <= not (i2c1_sda_tn_s and not i2c1_sda_o_s);

  gpio: for i in 0 to 95
  generate
    gpio_o(i).v <= gpio_o_s(i);
    gpio_o(i).en <= gpio_tn_s(i);
    gpio_i_s(i) <= gpio_i(i);
  end generate;

  registers: if report_registers_c
  generate
    assert false
      report register_note(16#FFD8#, 16#0118#, 16#00800000#, 16#00800000#,
                           "PMU_GLOBAL.REQ_PWRUP_INT_EN.PL")
      severity note;
    assert false
      report register_note(16#FFD8#, 16#0120#, 16#00800000#, 16#00800000#,
                           "PMU_GLOBAL.REQ_PWRUP_TRIG.PL, then poll REQ_PWRUP_STATUS.PL (0xFFD80110) for 0")
      severity note;

    assert false
      report register_note(16#FD61#, 16#5000#, 16#00000F00#,
                           afi_fs_width(m_axi_hpm0_fpd_config_c) * 16#100#
                           + afi_fs_width(m_axi_hpm1_fpd_config_c) * 16#400#,
                           "FPD_SLCR.AFI_FS, M_AXI_HPM0_FPD "
                           & width_comment(m_axi_hpm0_fpd_config_c)
                           & ", M_AXI_HPM1_FPD "
                           & width_comment(m_axi_hpm1_fpd_config_c))
      severity note;
    assert false
      report register_note(16#FF41#, 16#9000#, 16#00000300#,
                           afi_fs_width(m_axi_hpm0_lpd_config_c) * 16#100#,
                           "LPD_SLCR.AFI_FS, M_AXI_HPM0_LPD "
                           & width_comment(m_axi_hpm0_lpd_config_c))
      severity note;

    afifm: for n in 0 to 6
    generate
      constant comment_c : string
        := "CTRL.FABRIC_WIDTH, " & width_comment(s_config_c(n));
    begin
      assert false
        report register_note(afifm_page(n), afifm_rdctrl_c, 3, afifm_width(s_config_c(n)),
                             "AFIFM" & integer'image(n) & ".AFIFM_RD" & comment_c)
        severity note;
      assert false
        report register_note(afifm_page(n), afifm_wrctrl_c, 3, afifm_width(s_config_c(n)),
                             "AFIFM" & integer'image(n) & ".AFIFM_WR" & comment_c)
        severity note;
    end generate;

    pl_clock: for n in 0 to 3
    generate
      used: if pl_clock_frequency_c(n) /= 0
      generate
        assert false
          report "nsl_xilinx.ps8: pl clock " & integer'image(n)
          & " frequency " & integer'image(pl_clock_frequency_c(n)) & " Hz"
          severity note;
      end generate;
    end generate;
  end generate;

end architecture;
