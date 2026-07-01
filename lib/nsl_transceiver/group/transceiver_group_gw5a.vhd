library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_transceiver, nsl_io, nsl_amba, nsl_data, nsl_math, gowin;
use nsl_data.bytestream.all;
use nsl_math.int_ext.all;
use nsl_transceiver.target.all;

entity transceiver_group is
  generic(
    config_c : nsl_transceiver.group.config_t;
    ref_clock_c : integer_vector
    );
  port(
    reset_n_i : in std_ulogic;

    ref_clock_i : in std_ulogic_vector(0 to ref_clock_c'length-1);

    lane_tx_o : out nsl_io.diff.diff_pair_vector(0 to config_c.lane_count-1);
    lane_rx_i : in nsl_io.diff.diff_pair_vector(0 to config_c.lane_count-1);

    lane_tx_clock_o : out std_ulogic_vector(0 to config_c.lane_count-1);
    lane_rx_clock_o : out std_ulogic_vector(0 to config_c.lane_count-1);

    tx_m_i : in nsl_transceiver.lane.tx_master_vector(0 to config_c.lane_count-1);
    tx_s_o : out nsl_transceiver.lane.tx_slave_vector(0 to config_c.lane_count-1);
    rx_m_o : out nsl_transceiver.lane.rx_master_vector(0 to config_c.lane_count-1);
    rx_s_i : in nsl_transceiver.lane.rx_slave_vector(0 to config_c.lane_count-1);

    pma_reset_n_i : in std_ulogic_vector(0 to config_c.lane_count-1);

    -- APB clock for the user-facing master. Sourced internally from
    -- GTR12_QUADB's FABRIC_CM_LIFE_CLK_O loopback (the same clock
    -- the wizard uses for AHB / UPAR). The APB master and any
    -- companion logic on the configuration bus must clock on this
    -- output.
    apb_clock_o : out std_ulogic;
    apb_reset_n_i : in std_ulogic;
    apb_m_i : in nsl_amba.apb.master_t;
    apb_s_o : out nsl_amba.apb.slave_t
    );
end entity;

-- GW5A backend wrapping the GTR12_QUADB transceiver group
-- primitive. The primitive exposes a fixed 4-lane / 2-PLL /
-- 2-ref-clock shape; configurations that do not match are rejected
-- at elaboration.
--
-- Current scope: per-lane data path is wired with a uniform layout
-- targeted at 8b10b and 64b/66b (data bytes 0..7 at txdata[63:0],
-- per-byte aux bit 0 at txdata[71:64], unused bits zeroed; RX
-- symmetric, with the upper 16 RX bits surfaced through
-- rx_master.status). Per-lane PMA / PCS resets are routed; per-lane
-- BUFGs sit on the recovered/derived fabric clocks; elastic FIFO
-- controls drive the valid/ready handshake. PLL ref-clock routing,
-- rate selection, equalizer settings and CSR access via GTR12_UPARA
-- are not yet plumbed; APB slave continues to return an immediate
-- no-op response.
architecture gw5a of transceiver_group is

  component GTR12_QUADB is
    port(
      LN0_TXM_O : out std_logic;
      LN0_TXP_O : out std_logic;
      LN1_TXM_O : out std_logic;
      LN1_TXP_O : out std_logic;
      LN2_TXM_O : out std_logic;
      LN2_TXP_O : out std_logic;
      LN3_TXM_O : out std_logic;
      LN3_TXP_O : out std_logic;
      LN0_RXM_I : in std_logic;
      LN0_RXP_I : in std_logic;
      LN1_RXM_I : in std_logic;
      LN1_RXP_I : in std_logic;
      LN2_RXM_I : in std_logic;
      LN2_RXP_I : in std_logic;
      LN3_RXM_I : in std_logic;
      LN3_RXP_I : in std_logic;

      REFCLKP0_I : in std_logic;
      REFCLKM0_I : in std_logic;
      REFCLKP1_I : in std_logic;
      REFCLKM1_I : in std_logic;
      FABRIC_REFCLK_INPUT_SEL_I : in std_logic_vector(2 downto 0);
      FABRIC_REFCLK1_INPUT_SEL_I : in std_logic_vector(2 downto 0);
      FABRIC_PMA_PD_REFHCLK_I : in std_logic;
      FABRIC_REFCLK_GATE_I : in std_logic;
      FABRIC_REFCLK_GATE_ACK_O : out std_logic;
      FABRIC_CMU_REFCLK_GATE_I : in std_logic;
      FABRIC_CMU_REFCLK_GATE_ACK_O : out std_logic;
      FABRIC_CMU1_REFCLK_GATE_I : in std_logic;
      FABRIC_CMU1_REFCLK_GATE_ACK_O : out std_logic;

      FABRIC_CMU0_RESETN_I : in std_logic;
      FABRIC_CMU0_PD_I : in std_logic;
      FABRIC_CMU0_IDDQ_I : in std_logic;
      FABRIC_CMU1_RESETN_I : in std_logic;
      FABRIC_CMU1_PD_I : in std_logic;
      FABRIC_CMU1_IDDQ_I : in std_logic;
      FABRIC_PLL_CDN_I : in std_logic;
      FABRIC_CMU_OK_O : out std_logic;
      FABRIC_CMU1_OK_O : out std_logic;
      FABRIC_CMU_CK_REF_O : out std_logic;
      FABRIC_CMU1_CK_REF_O : out std_logic;
      FABRIC_CMU0_CLK : out std_logic;
      FABRIC_CMU1_CLK : out std_logic;
      FABRIC_CM_LIFE_CLK_O : out std_logic;
      FABRIC_CM1_LIFE_CLK_O : out std_logic;
      FABRIC_PMA_CM0_DR_REFCLK_DET_O : out std_logic;
      FABRIC_PMA_CM1_DR_REFCLK_DET_O : out std_logic;
      FABRIC_PMA_CM2_DR_REFCLK_DET_O : out std_logic;
      FABRIC_PMA_CM3_DR_REFCLK_DET_O : out std_logic;
      FABRIC_CM0_PD_REFCLK_DET_I : in std_logic;
      FABRIC_CM1_PD_REFCLK_DET_I : in std_logic;
      FABRIC_CM2_PD_REFCLK_DET_I : in std_logic;
      FABRIC_CM3_PD_REFCLK_DET_I : in std_logic;

      FABRIC_LN0_CPLL_RESETN_I : in std_logic;
      FABRIC_LN0_CPLL_PD_I : in std_logic;
      FABRIC_LN0_CPLL_IDDQ_I : in std_logic;
      FABRIC_LN1_CPLL_RESETN_I : in std_logic;
      FABRIC_LN1_CPLL_PD_I : in std_logic;
      FABRIC_LN1_CPLL_IDDQ_I : in std_logic;
      FABRIC_LN2_CPLL_RESETN_I : in std_logic;
      FABRIC_LN2_CPLL_PD_I : in std_logic;
      FABRIC_LN2_CPLL_IDDQ_I : in std_logic;
      FABRIC_LN3_CPLL_RESETN_I : in std_logic;
      FABRIC_LN3_CPLL_PD_I : in std_logic;
      FABRIC_LN3_CPLL_IDDQ_I : in std_logic;
      FABRIC_LANE0_CMU_OK_O : out std_logic;
      FABRIC_LANE1_CMU_OK_O : out std_logic;
      FABRIC_LANE2_CMU_OK_O : out std_logic;
      FABRIC_LANE3_CMU_OK_O : out std_logic;
      FABRIC_LANE0_CMU_CK_REF_O : out std_logic;
      FABRIC_LANE1_CMU_CK_REF_O : out std_logic;
      FABRIC_LANE2_CMU_CK_REF_O : out std_logic;
      FABRIC_LANE3_CMU_CK_REF_O : out std_logic;

      FABRIC_LN0_RSTN_I : in std_logic;
      FABRIC_LN1_RSTN_I : in std_logic;
      FABRIC_LN2_RSTN_I : in std_logic;
      FABRIC_LN3_RSTN_I : in std_logic;
      FABRIC_LN0_IDDQ_I : in std_logic;
      FABRIC_LN1_IDDQ_I : in std_logic;
      FABRIC_LN2_IDDQ_I : in std_logic;
      FABRIC_LN3_IDDQ_I : in std_logic;
      FABRIC_LN0_PD_I : in std_logic_vector(2 downto 0);
      FABRIC_LN1_PD_I : in std_logic_vector(2 downto 0);
      FABRIC_LN2_PD_I : in std_logic_vector(2 downto 0);
      FABRIC_LN3_PD_I : in std_logic_vector(2 downto 0);
      FABRIC_LN0_RATE_I : in std_logic_vector(1 downto 0);
      FABRIC_LN1_RATE_I : in std_logic_vector(1 downto 0);
      FABRIC_LN2_RATE_I : in std_logic_vector(1 downto 0);
      FABRIC_LN3_RATE_I : in std_logic_vector(1 downto 0);
      FABRIC_LN0_CTRL_I : in std_logic_vector(42 downto 0);
      FABRIC_LN1_CTRL_I : in std_logic_vector(42 downto 0);
      FABRIC_LN2_CTRL_I : in std_logic_vector(42 downto 0);
      FABRIC_LN3_CTRL_I : in std_logic_vector(42 downto 0);
      FABRIC_LN0_PD_I_H : in std_logic_vector(2 downto 0);
      FABRIC_LN1_PD_I_H : in std_logic_vector(2 downto 0);
      FABRIC_LN2_PD_I_H : in std_logic_vector(2 downto 0);
      FABRIC_LN3_PD_I_H : in std_logic_vector(2 downto 0);
      FABRIC_LN0_RATE_I_H : in std_logic_vector(1 downto 0);
      FABRIC_LN1_RATE_I_H : in std_logic_vector(1 downto 0);
      FABRIC_LN2_RATE_I_H : in std_logic_vector(1 downto 0);
      FABRIC_LN3_RATE_I_H : in std_logic_vector(1 downto 0);
      FABRIC_LN0_CTRL_I_H : in std_logic_vector(42 downto 0);
      FABRIC_LN1_CTRL_I_H : in std_logic_vector(42 downto 0);
      FABRIC_LN2_CTRL_I_H : in std_logic_vector(42 downto 0);
      FABRIC_LN3_CTRL_I_H : in std_logic_vector(42 downto 0);

      FABRIC_LN0_TXDATA_I : in std_logic_vector(79 downto 0);
      FABRIC_LN1_TXDATA_I : in std_logic_vector(79 downto 0);
      FABRIC_LN2_TXDATA_I : in std_logic_vector(79 downto 0);
      FABRIC_LN3_TXDATA_I : in std_logic_vector(79 downto 0);
      FABRIC_LN0_RXDATA_O : out std_logic_vector(87 downto 0);
      FABRIC_LN1_RXDATA_O : out std_logic_vector(87 downto 0);
      FABRIC_LN2_RXDATA_O : out std_logic_vector(87 downto 0);
      FABRIC_LN3_RXDATA_O : out std_logic_vector(87 downto 0);
      FABRIC_LN0_TX_VLD_IN : in std_logic;
      FABRIC_LN1_TX_VLD_IN : in std_logic;
      FABRIC_LN2_TX_VLD_IN : in std_logic;
      FABRIC_LN3_TX_VLD_IN : in std_logic;
      FABRIC_LN0_RX_VLD_OUT : out std_logic;
      FABRIC_LN1_RX_VLD_OUT : out std_logic;
      FABRIC_LN2_RX_VLD_OUT : out std_logic;
      FABRIC_LN3_RX_VLD_OUT : out std_logic;
      FABRIC_LN0_TX_DISPARITY_I : in std_logic_vector(7 downto 0);
      FABRIC_LN1_TX_DISPARITY_I : in std_logic_vector(7 downto 0);
      FABRIC_LN2_TX_DISPARITY_I : in std_logic_vector(7 downto 0);
      FABRIC_LN3_TX_DISPARITY_I : in std_logic_vector(7 downto 0);

      FABRIC_LN0_ASTAT_O : out std_logic_vector(5 downto 0);
      FABRIC_LN1_ASTAT_O : out std_logic_vector(5 downto 0);
      FABRIC_LN2_ASTAT_O : out std_logic_vector(5 downto 0);
      FABRIC_LN3_ASTAT_O : out std_logic_vector(5 downto 0);
      FABRIC_LN0_STAT_O : out std_logic_vector(12 downto 0);
      FABRIC_LN1_STAT_O : out std_logic_vector(12 downto 0);
      FABRIC_LN2_STAT_O : out std_logic_vector(12 downto 0);
      FABRIC_LN3_STAT_O : out std_logic_vector(12 downto 0);
      FABRIC_LN0_STAT_O_H : out std_logic_vector(12 downto 0);
      FABRIC_LN1_STAT_O_H : out std_logic_vector(12 downto 0);
      FABRIC_LN2_STAT_O_H : out std_logic_vector(12 downto 0);
      FABRIC_LN3_STAT_O_H : out std_logic_vector(12 downto 0);
      FABRIC_LN0_PMA_RX_LOCK_O : out std_logic;
      FABRIC_LN1_PMA_RX_LOCK_O : out std_logic;
      FABRIC_LN2_PMA_RX_LOCK_O : out std_logic;
      FABRIC_LN3_PMA_RX_LOCK_O : out std_logic;
      FABRIC_LN0_RXELECIDLE_O : out std_logic;
      FABRIC_LN1_RXELECIDLE_O : out std_logic;
      FABRIC_LN2_RXELECIDLE_O : out std_logic;
      FABRIC_LN3_RXELECIDLE_O : out std_logic;
      FABRIC_LN0_RXELECIDLE_O_H : out std_logic;
      FABRIC_LN1_RXELECIDLE_O_H : out std_logic;
      FABRIC_LN2_RXELECIDLE_O_H : out std_logic;
      FABRIC_LN3_RXELECIDLE_O_H : out std_logic;
      FABRIC_LN0_RXDET_RESULT : out std_logic;
      FABRIC_LN1_RXDET_RESULT : out std_logic;
      FABRIC_LN2_RXDET_RESULT : out std_logic;
      FABRIC_LN3_RXDET_RESULT : out std_logic;
      FABRIC_LN0_BURN_IN_TOGGLE_O : out std_logic;
      FABRIC_LN1_BURN_IN_TOGGLE_O : out std_logic;
      FABRIC_LN2_BURN_IN_TOGGLE_O : out std_logic;
      FABRIC_LN3_BURN_IN_TOGGLE_O : out std_logic;

      LANE0_ALIGN_LINK : out std_logic;
      LANE1_ALIGN_LINK : out std_logic;
      LANE2_ALIGN_LINK : out std_logic;
      LANE3_ALIGN_LINK : out std_logic;
      LANE0_K_LOCK : out std_logic;
      LANE1_K_LOCK : out std_logic;
      LANE2_K_LOCK : out std_logic;
      LANE3_K_LOCK : out std_logic;
      LANE0_DISP_ERR_O : out std_logic_vector(1 downto 0);
      LANE1_DISP_ERR_O : out std_logic_vector(1 downto 0);
      LANE2_DISP_ERR_O : out std_logic_vector(1 downto 0);
      LANE3_DISP_ERR_O : out std_logic_vector(1 downto 0);
      LANE0_DEC_ERR_O : out std_logic_vector(1 downto 0);
      LANE1_DEC_ERR_O : out std_logic_vector(1 downto 0);
      LANE2_DEC_ERR_O : out std_logic_vector(1 downto 0);
      LANE3_DEC_ERR_O : out std_logic_vector(1 downto 0);
      LANE0_CUR_DISP_O : out std_logic_vector(1 downto 0);
      LANE1_CUR_DISP_O : out std_logic_vector(1 downto 0);
      LANE2_CUR_DISP_O : out std_logic_vector(1 downto 0);
      LANE3_CUR_DISP_O : out std_logic_vector(1 downto 0);
      LANE0_ALIGN_TRIGGER : in std_logic;
      LANE1_ALIGN_TRIGGER : in std_logic;
      LANE2_ALIGN_TRIGGER : in std_logic;
      LANE3_ALIGN_TRIGGER : in std_logic;
      LANE0_CHBOND_START : in std_logic;
      LANE1_CHBOND_START : in std_logic;
      LANE2_CHBOND_START : in std_logic;
      LANE3_CHBOND_START : in std_logic;
      LANE0_PCS_TX_RST : in std_logic;
      LANE1_PCS_TX_RST : in std_logic;
      LANE2_PCS_TX_RST : in std_logic;
      LANE3_PCS_TX_RST : in std_logic;
      LANE0_PCS_RX_RST : in std_logic;
      LANE1_PCS_RX_RST : in std_logic;
      LANE2_PCS_RX_RST : in std_logic;
      LANE3_PCS_RX_RST : in std_logic;

      LANE0_PCS_TX_O_FABRIC_CLK : out std_logic;
      LANE1_PCS_TX_O_FABRIC_CLK : out std_logic;
      LANE2_PCS_TX_O_FABRIC_CLK : out std_logic;
      LANE3_PCS_TX_O_FABRIC_CLK : out std_logic;
      LANE0_PCS_RX_O_FABRIC_CLK : out std_logic;
      LANE1_PCS_RX_O_FABRIC_CLK : out std_logic;
      LANE2_PCS_RX_O_FABRIC_CLK : out std_logic;
      LANE3_PCS_RX_O_FABRIC_CLK : out std_logic;
      LANE0_FABRIC_TX_CLK : in std_logic;
      LANE1_FABRIC_TX_CLK : in std_logic;
      LANE2_FABRIC_TX_CLK : in std_logic;
      LANE3_FABRIC_TX_CLK : in std_logic;
      LANE0_FABRIC_RX_CLK : in std_logic;
      LANE1_FABRIC_RX_CLK : in std_logic;
      LANE2_FABRIC_RX_CLK : in std_logic;
      LANE3_FABRIC_RX_CLK : in std_logic;
      LANE0_FABRIC_C2I_CLK : in std_logic;
      LANE1_FABRIC_C2I_CLK : in std_logic;
      LANE2_FABRIC_C2I_CLK : in std_logic;
      LANE3_FABRIC_C2I_CLK : in std_logic;
      FABRIC_QUAD_CLK_RX : out std_logic;

      LANE0_RX_IF_FIFO_RDEN : in std_logic;
      LANE1_RX_IF_FIFO_RDEN : in std_logic;
      LANE2_RX_IF_FIFO_RDEN : in std_logic;
      LANE3_RX_IF_FIFO_RDEN : in std_logic;
      LANE0_RX_IF_FIFO_AEMPTY : out std_logic;
      LANE1_RX_IF_FIFO_AEMPTY : out std_logic;
      LANE2_RX_IF_FIFO_AEMPTY : out std_logic;
      LANE3_RX_IF_FIFO_AEMPTY : out std_logic;
      LANE0_RX_IF_FIFO_EMPTY : out std_logic;
      LANE1_RX_IF_FIFO_EMPTY : out std_logic;
      LANE2_RX_IF_FIFO_EMPTY : out std_logic;
      LANE3_RX_IF_FIFO_EMPTY : out std_logic;
      LANE0_RX_IF_FIFO_RDUSEWD : out std_logic_vector(4 downto 0);
      LANE1_RX_IF_FIFO_RDUSEWD : out std_logic_vector(4 downto 0);
      LANE2_RX_IF_FIFO_RDUSEWD : out std_logic_vector(4 downto 0);
      LANE3_RX_IF_FIFO_RDUSEWD : out std_logic_vector(4 downto 0);
      LANE0_TX_IF_FIFO_AFULL : out std_logic;
      LANE1_TX_IF_FIFO_AFULL : out std_logic;
      LANE2_TX_IF_FIFO_AFULL : out std_logic;
      LANE3_TX_IF_FIFO_AFULL : out std_logic;
      LANE0_TX_IF_FIFO_FULL : out std_logic;
      LANE1_TX_IF_FIFO_FULL : out std_logic;
      LANE2_TX_IF_FIFO_FULL : out std_logic;
      LANE3_TX_IF_FIFO_FULL : out std_logic;
      LANE0_TX_IF_FIFO_WRUSEWD : out std_logic_vector(4 downto 0);
      LANE1_TX_IF_FIFO_WRUSEWD : out std_logic_vector(4 downto 0);
      LANE2_TX_IF_FIFO_WRUSEWD : out std_logic_vector(4 downto 0);
      LANE3_TX_IF_FIFO_WRUSEWD : out std_logic_vector(4 downto 0);

      FABRIC_LANE0_64B66B_TX_INVLD_BLK : out std_logic;
      FABRIC_LANE1_64B66B_TX_INVLD_BLK : out std_logic;
      FABRIC_LANE2_64B66B_TX_INVLD_BLK : out std_logic;
      FABRIC_LANE3_64B66B_TX_INVLD_BLK : out std_logic;
      FABRIC_LANE0_64B66B_TX_FETCH : out std_logic;
      FABRIC_LANE1_64B66B_TX_FETCH : out std_logic;
      FABRIC_LANE2_64B66B_TX_FETCH : out std_logic;
      FABRIC_LANE3_64B66B_TX_FETCH : out std_logic;
      FABRIC_LANE0_64B66B_RX_VALID : out std_logic;
      FABRIC_LANE1_64B66B_RX_VALID : out std_logic;
      FABRIC_LANE2_64B66B_RX_VALID : out std_logic;
      FABRIC_LANE3_64B66B_RX_VALID : out std_logic;

      CKP_MIPI_0 : out std_logic;
      CKP_MIPI_1 : out std_logic;
      CKN_MIPI_0 : out std_logic;
      CKN_MIPI_1 : out std_logic;

      FABRIC_CLK_REF_CORE_I : in std_logic_vector(3 downto 0);
      FABRIC_CK_SOC_DIV_I : in std_logic_vector(1 downto 0);
      FABRIC_BURN_IN_I : in std_logic;
      FABRIC_GLUE_MAC_INIT_INFO_I : in std_logic;
      FABRIC_GEARFIFO_ERR_RPT : out std_logic;
      FABRIC_CLK_MON_O : out std_logic;
      FABRIC_POR_N_I : in std_logic;
      FABRIC_QUAD_MCU_REQ_I : in std_logic;
      CK_AHB_I : in std_logic;
      AHB_RSTN : in std_logic;
      TEST_DEC_EN : in std_logic;
      QUAD_PCLK0 : out std_logic;
      QUAD_PCLK1 : out std_logic;
      QUAD_PCIE_CLK : in std_logic;
      PCIE_DIV2_REG : in std_logic;
      PCIE_DIV4_REG : in std_logic;
      PMAC_LN_RSTN : in std_logic;
      CLK_VIQ_I : in std_logic_vector(1 downto 0)
      );
  end component;

  type tx_data_array_t is array (0 to 3) of std_logic_vector(79 downto 0);
  type rx_data_array_t is array (0 to 3) of std_logic_vector(87 downto 0);

  signal s_tx_data : tx_data_array_t;
  signal s_rx_data : rx_data_array_t;

  signal s_lane_pcs_tx_clk_raw : std_logic_vector(0 to 3);
  signal s_lane_pcs_rx_clk_raw : std_logic_vector(0 to 3);
  signal s_lane_pcs_tx_clk_buf : std_logic_vector(0 to 3);
  signal s_lane_pcs_rx_clk_buf : std_logic_vector(0 to 3);

  signal s_tx_fifo_afull : std_logic_vector(0 to 3);
  signal s_rx_fifo_aempty : std_logic_vector(0 to 3);
  signal s_tx_vld_in : std_logic_vector(0 to 3);
  signal s_rx_vld_out : std_logic_vector(0 to 3);
  signal s_rx_fifo_rden : std_logic_vector(0 to 3);
  signal s_pcs_tx_rst : std_logic_vector(0 to 3);
  signal s_pcs_rx_rst : std_logic_vector(0 to 3);
  signal s_lane_rstn : std_logic_vector(0 to 3);
  signal s_align_trigger : std_logic_vector(0 to 3);
  signal s_chbond_start : std_logic_vector(0 to 3);

  signal s_pma_rx_lock : std_logic_vector(0 to 3);
  signal s_align_link : std_logic_vector(0 to 3);
  signal s_rxelecidle : std_logic_vector(0 to 3);

  type ctrl_array_t is array (0 to 3) of std_logic_vector(42 downto 0);
  signal s_lane_ctrl : ctrl_array_t;
  signal s_lane_ctrl_h : ctrl_array_t;
  signal s_lane_c2i_clk : std_logic_vector(0 to 3);

  signal s_cmu0_ok : std_logic;
  signal s_cmu1_ok : std_logic;

  signal s_cm_life_clk_raw : std_logic;
  signal s_apb_clock : std_ulogic;
  signal s_ahb_reset_n : std_ulogic;
  signal s_test_dec_en : std_ulogic;

  -- CLK_VIQ_I fabric slots. Bit 0 receives the ref_clock_i entry
  -- tagged clock_id("fabric"); bit 1 receives the entry tagged
  -- clock_id("mclk"). Zero when the corresponding source is not
  -- listed in ref_clock_c.
  signal s_clk_viq : std_ulogic_vector(1 downto 0) := (others => '0');

  signal gw_gnd : std_logic := '0';
  signal gw_vcc : std_logic := '1';

begin

  assert config_c.lane_count = 4
    report "transceiver_group/gw5a: GTR12_QUADB primitive requires exactly 4 lanes"
    severity failure;
  assert config_c.pll_count <= 2
    report "transceiver_group/gw5a: GTR12_QUADB exposes at most 2 quad-shared PLLs (CMU0/CMU1)"
    severity failure;
  assert ref_clock_c'length <= 4
    report "transceiver_group/gw5a: GTR12_QUADB exposes at most 4 fabric-side reference clock inputs (ref0/ref1/fabric/mclk)"
    severity failure;
  assert nsl_transceiver.group.is_valid(config_c)
    report "transceiver_group/gw5a: configuration failed target-agnostic consistency check"
    severity failure;

  encoding_check: for lane_idx in 0 to config_c.lane_count-1 generate
    encoding_supported: if config_c.lanes(lane_idx).enabled generate
      assert config_c.lanes(lane_idx).encoding = nsl_transceiver.lane.ENCODING_RAW
          or config_c.lanes(lane_idx).encoding = nsl_transceiver.lane.ENCODING_8B10B
          or config_c.lanes(lane_idx).encoding = nsl_transceiver.lane.ENCODING_64B66B
        report "transceiver_group/gw5a: lane encoding not supported by this backend yet"
        severity failure;
      assert config_c.lanes(lane_idx).data_byte_count = 8
        report "transceiver_group/gw5a: lane data_byte_count must be 8 in the current data path mapping"
        severity failure;
    end generate;
  end generate;

  -- Reference clock source routing. Each ref_clock_i entry is
  -- driven onto the primitive input matching the target-defined
  -- identifier in ref_clock_c(i). "ref0" and "ref1" are pad-based
  -- and handled by the FPGA pin constraints; their fabric-side
  -- ports are left at ground, matching the wizard. "fabric" and
  -- "mclk" drive the CLK_VIQ_I fabric slots.
  ref_clock_route: for i in 0 to ref_clock_c'length-1 generate
    is_fabric: if ref_clock_c(i) = clock_id("fabric") generate
      s_clk_viq(0) <= ref_clock_i(i);
    end generate;
    is_mclk: if ref_clock_c(i) = clock_id("mclk") generate
      s_clk_viq(1) <= ref_clock_i(i);
    end generate;
  end generate;

  lane_wire: for lane_idx in 0 to 3 generate

    enabled_lane: if config_c.lanes(lane_idx).enabled generate

      tx_pack: for byte_idx in 0 to 7 generate
        s_tx_data(lane_idx)(8*byte_idx+7 downto 8*byte_idx)
          <= std_logic_vector(tx_m_i(lane_idx).data(byte_idx));
        s_tx_data(lane_idx)(64+byte_idx) <= tx_m_i(lane_idx).aux(byte_idx)(0);
      end generate;
      s_tx_data(lane_idx)(79 downto 72) <= (others => '0');

      rx_unpack: for byte_idx in 0 to 7 generate
        rx_m_o(lane_idx).data(byte_idx)
          <= std_ulogic_vector(s_rx_data(lane_idx)(8*byte_idx+7 downto 8*byte_idx));
        rx_m_o(lane_idx).aux(byte_idx)
          <= (0 => s_rx_data(lane_idx)(64+byte_idx), others => '0');
      end generate;
      rx_data_unused: for byte_idx in 8 to 31 generate
        rx_m_o(lane_idx).data(byte_idx) <= (others => '0');
        rx_m_o(lane_idx).aux(byte_idx) <= (others => '0');
      end generate;
      rx_m_o(lane_idx).status(15 downto 0)
        <= std_ulogic_vector(s_rx_data(lane_idx)(87 downto 72));
      rx_m_o(lane_idx).status(31 downto 16) <= (others => '0');

      rx_m_o(lane_idx).valid <= s_rx_vld_out(lane_idx);
      rx_m_o(lane_idx).pma_lock <= s_pma_rx_lock(lane_idx);
      rx_m_o(lane_idx).pcs_aligned <= s_align_link(lane_idx);
      rx_m_o(lane_idx).elec_idle <= s_rxelecidle(lane_idx);

      tx_s_o(lane_idx).ready <= not s_tx_fifo_afull(lane_idx);
      tx_s_o(lane_idx).pll_lock <= s_cmu0_ok
        when config_c.lanes(lane_idx).pll_index = 0
        else s_cmu1_ok;
      tx_s_o(lane_idx).status <= (others => '0');

      s_pcs_tx_rst(lane_idx) <= not tx_m_i(lane_idx).pcs_reset_n;
      s_pcs_rx_rst(lane_idx) <= not rx_s_i(lane_idx).pcs_reset_n;
      s_lane_rstn(lane_idx) <= pma_reset_n_i(lane_idx);
      s_tx_vld_in(lane_idx) <= tx_m_i(lane_idx).valid;
      s_rx_fifo_rden(lane_idx) <= rx_s_i(lane_idx).ready;
      s_align_trigger(lane_idx) <= rx_s_i(lane_idx).align_trigger;
      s_chbond_start(lane_idx) <= rx_s_i(lane_idx).chbond_start;
      s_lane_ctrl(lane_idx) <= std_logic_vector(tx_m_i(lane_idx).control(42 downto 0));
      s_lane_ctrl_h(lane_idx) <= std_logic_vector(tx_m_i(lane_idx).control_h(42 downto 0));
      s_lane_c2i_clk(lane_idx) <= tx_m_i(lane_idx).c2i_clock;

      tx_bufg: gowin.components.bufg
        port map(
          i => s_lane_pcs_tx_clk_raw(lane_idx),
          o => s_lane_pcs_tx_clk_buf(lane_idx)
          );
      rx_bufg: gowin.components.bufg
        port map(
          i => s_lane_pcs_rx_clk_raw(lane_idx),
          o => s_lane_pcs_rx_clk_buf(lane_idx)
          );
      lane_tx_clock_o(lane_idx) <= s_lane_pcs_tx_clk_buf(lane_idx);
      lane_rx_clock_o(lane_idx) <= s_lane_pcs_rx_clk_buf(lane_idx);

    end generate;

    disabled_lane: if not config_c.lanes(lane_idx).enabled generate
      s_tx_data(lane_idx) <= (others => '0');
      rx_m_o(lane_idx) <= nsl_transceiver.lane.null_rx_master_c;
      tx_s_o(lane_idx) <= nsl_transceiver.lane.null_tx_slave_c;
      s_pcs_tx_rst(lane_idx) <= '0';
      s_pcs_rx_rst(lane_idx) <= '0';
      s_lane_rstn(lane_idx) <= '0';
      s_tx_vld_in(lane_idx) <= '0';
      s_rx_fifo_rden(lane_idx) <= '0';
      s_align_trigger(lane_idx) <= '0';
      s_chbond_start(lane_idx) <= '0';
      s_lane_ctrl(lane_idx) <= (others => '0');
      s_lane_ctrl_h(lane_idx) <= (others => '0');
      s_lane_c2i_clk(lane_idx) <= '0';
      s_lane_pcs_tx_clk_buf(lane_idx) <= '0';
      s_lane_pcs_rx_clk_buf(lane_idx) <= '0';
      lane_tx_clock_o(lane_idx) <= '0';
      lane_rx_clock_o(lane_idx) <= '0';
    end generate;

  end generate;

  quad: GTR12_QUADB
    port map(
      LN0_TXM_O => lane_tx_o(0).n,
      LN0_TXP_O => lane_tx_o(0).p,
      LN1_TXM_O => lane_tx_o(1).n,
      LN1_TXP_O => lane_tx_o(1).p,
      LN2_TXM_O => lane_tx_o(2).n,
      LN2_TXP_O => lane_tx_o(2).p,
      LN3_TXM_O => lane_tx_o(3).n,
      LN3_TXP_O => lane_tx_o(3).p,
      LN0_RXM_I => lane_rx_i(0).n,
      LN0_RXP_I => lane_rx_i(0).p,
      LN1_RXM_I => lane_rx_i(1).n,
      LN1_RXP_I => lane_rx_i(1).p,
      LN2_RXM_I => lane_rx_i(2).n,
      LN2_RXP_I => lane_rx_i(2).p,
      LN3_RXM_I => lane_rx_i(3).n,
      LN3_RXP_I => lane_rx_i(3).p,

      -- Pad reference clocks. The primitive treats these ports as
      -- decorative: the actual pin routing is fixed by the FPGA
      -- pad constraints, and the wizard-generated wrapper leaves
      -- them at ground.
      REFCLKP0_I => gw_gnd,
      REFCLKM0_I => gw_gnd,
      REFCLKP1_I => gw_gnd,
      REFCLKM1_I => gw_gnd,
      FABRIC_REFCLK_INPUT_SEL_I => "000",
      FABRIC_REFCLK1_INPUT_SEL_I => "000",
      FABRIC_PMA_PD_REFHCLK_I => gw_gnd,
      FABRIC_REFCLK_GATE_I => gw_gnd,
      FABRIC_REFCLK_GATE_ACK_O => open,
      FABRIC_CMU_REFCLK_GATE_I => gw_gnd,
      FABRIC_CMU_REFCLK_GATE_ACK_O => open,
      FABRIC_CMU1_REFCLK_GATE_I => gw_gnd,
      FABRIC_CMU1_REFCLK_GATE_ACK_O => open,

      FABRIC_CMU0_RESETN_I => gw_gnd,
      FABRIC_CMU0_PD_I => gw_gnd,
      FABRIC_CMU0_IDDQ_I => gw_gnd,
      FABRIC_CMU1_RESETN_I => gw_gnd,
      FABRIC_CMU1_PD_I => gw_gnd,
      FABRIC_CMU1_IDDQ_I => gw_gnd,
      FABRIC_PLL_CDN_I => gw_gnd,
      FABRIC_CMU_OK_O => s_cmu0_ok,
      FABRIC_CMU1_OK_O => s_cmu1_ok,
      FABRIC_CMU_CK_REF_O => open,
      FABRIC_CMU1_CK_REF_O => open,
      FABRIC_CMU0_CLK => open,
      FABRIC_CMU1_CLK => open,
      FABRIC_CM_LIFE_CLK_O => s_cm_life_clk_raw,
      FABRIC_CM1_LIFE_CLK_O => open,
      FABRIC_PMA_CM0_DR_REFCLK_DET_O => open,
      FABRIC_PMA_CM1_DR_REFCLK_DET_O => open,
      FABRIC_PMA_CM2_DR_REFCLK_DET_O => open,
      FABRIC_PMA_CM3_DR_REFCLK_DET_O => open,
      FABRIC_CM0_PD_REFCLK_DET_I => gw_gnd,
      FABRIC_CM1_PD_REFCLK_DET_I => gw_gnd,
      FABRIC_CM2_PD_REFCLK_DET_I => gw_gnd,
      FABRIC_CM3_PD_REFCLK_DET_I => gw_gnd,

      FABRIC_LN0_CPLL_RESETN_I => gw_gnd,
      FABRIC_LN0_CPLL_PD_I => gw_gnd,
      FABRIC_LN0_CPLL_IDDQ_I => gw_gnd,
      FABRIC_LN1_CPLL_RESETN_I => gw_gnd,
      FABRIC_LN1_CPLL_PD_I => gw_gnd,
      FABRIC_LN1_CPLL_IDDQ_I => gw_gnd,
      FABRIC_LN2_CPLL_RESETN_I => gw_gnd,
      FABRIC_LN2_CPLL_PD_I => gw_gnd,
      FABRIC_LN2_CPLL_IDDQ_I => gw_gnd,
      FABRIC_LN3_CPLL_RESETN_I => gw_gnd,
      FABRIC_LN3_CPLL_PD_I => gw_gnd,
      FABRIC_LN3_CPLL_IDDQ_I => gw_gnd,
      FABRIC_LANE0_CMU_OK_O => open,
      FABRIC_LANE1_CMU_OK_O => open,
      FABRIC_LANE2_CMU_OK_O => open,
      FABRIC_LANE3_CMU_OK_O => open,
      FABRIC_LANE0_CMU_CK_REF_O => open,
      FABRIC_LANE1_CMU_CK_REF_O => open,
      FABRIC_LANE2_CMU_CK_REF_O => open,
      FABRIC_LANE3_CMU_CK_REF_O => open,

      FABRIC_LN0_RSTN_I => s_lane_rstn(0),
      FABRIC_LN1_RSTN_I => s_lane_rstn(1),
      FABRIC_LN2_RSTN_I => s_lane_rstn(2),
      FABRIC_LN3_RSTN_I => s_lane_rstn(3),
      FABRIC_LN0_IDDQ_I => gw_gnd,
      FABRIC_LN1_IDDQ_I => gw_gnd,
      FABRIC_LN2_IDDQ_I => gw_gnd,
      FABRIC_LN3_IDDQ_I => gw_gnd,
      FABRIC_LN0_PD_I => "000",
      FABRIC_LN1_PD_I => "000",
      FABRIC_LN2_PD_I => "000",
      FABRIC_LN3_PD_I => "000",
      FABRIC_LN0_RATE_I => "00",
      FABRIC_LN1_RATE_I => "00",
      FABRIC_LN2_RATE_I => "00",
      FABRIC_LN3_RATE_I => "00",
      FABRIC_LN0_CTRL_I => s_lane_ctrl(0),
      FABRIC_LN1_CTRL_I => s_lane_ctrl(1),
      FABRIC_LN2_CTRL_I => s_lane_ctrl(2),
      FABRIC_LN3_CTRL_I => s_lane_ctrl(3),
      FABRIC_LN0_CTRL_I_H => s_lane_ctrl_h(0),
      FABRIC_LN1_CTRL_I_H => s_lane_ctrl_h(1),
      FABRIC_LN2_CTRL_I_H => s_lane_ctrl_h(2),
      FABRIC_LN3_CTRL_I_H => s_lane_ctrl_h(3),
      FABRIC_LN0_PD_I_H => "000",
      FABRIC_LN1_PD_I_H => "000",
      FABRIC_LN2_PD_I_H => "000",
      FABRIC_LN3_PD_I_H => "000",
      FABRIC_LN0_RATE_I_H => "00",
      FABRIC_LN1_RATE_I_H => "00",
      FABRIC_LN2_RATE_I_H => "00",
      FABRIC_LN3_RATE_I_H => "00",

      FABRIC_LN0_TXDATA_I => s_tx_data(0),
      FABRIC_LN1_TXDATA_I => s_tx_data(1),
      FABRIC_LN2_TXDATA_I => s_tx_data(2),
      FABRIC_LN3_TXDATA_I => s_tx_data(3),
      FABRIC_LN0_RXDATA_O => s_rx_data(0),
      FABRIC_LN1_RXDATA_O => s_rx_data(1),
      FABRIC_LN2_RXDATA_O => s_rx_data(2),
      FABRIC_LN3_RXDATA_O => s_rx_data(3),
      FABRIC_LN0_TX_VLD_IN => s_tx_vld_in(0),
      FABRIC_LN1_TX_VLD_IN => s_tx_vld_in(1),
      FABRIC_LN2_TX_VLD_IN => s_tx_vld_in(2),
      FABRIC_LN3_TX_VLD_IN => s_tx_vld_in(3),
      FABRIC_LN0_RX_VLD_OUT => s_rx_vld_out(0),
      FABRIC_LN1_RX_VLD_OUT => s_rx_vld_out(1),
      FABRIC_LN2_RX_VLD_OUT => s_rx_vld_out(2),
      FABRIC_LN3_RX_VLD_OUT => s_rx_vld_out(3),
      FABRIC_LN0_TX_DISPARITY_I => (others => '0'),
      FABRIC_LN1_TX_DISPARITY_I => (others => '0'),
      FABRIC_LN2_TX_DISPARITY_I => (others => '0'),
      FABRIC_LN3_TX_DISPARITY_I => (others => '0'),

      FABRIC_LN0_ASTAT_O => open,
      FABRIC_LN1_ASTAT_O => open,
      FABRIC_LN2_ASTAT_O => open,
      FABRIC_LN3_ASTAT_O => open,
      FABRIC_LN0_STAT_O => open,
      FABRIC_LN1_STAT_O => open,
      FABRIC_LN2_STAT_O => open,
      FABRIC_LN3_STAT_O => open,
      FABRIC_LN0_STAT_O_H => open,
      FABRIC_LN1_STAT_O_H => open,
      FABRIC_LN2_STAT_O_H => open,
      FABRIC_LN3_STAT_O_H => open,
      FABRIC_LN0_PMA_RX_LOCK_O => s_pma_rx_lock(0),
      FABRIC_LN1_PMA_RX_LOCK_O => s_pma_rx_lock(1),
      FABRIC_LN2_PMA_RX_LOCK_O => s_pma_rx_lock(2),
      FABRIC_LN3_PMA_RX_LOCK_O => s_pma_rx_lock(3),
      FABRIC_LN0_RXELECIDLE_O => s_rxelecidle(0),
      FABRIC_LN1_RXELECIDLE_O => s_rxelecidle(1),
      FABRIC_LN2_RXELECIDLE_O => s_rxelecidle(2),
      FABRIC_LN3_RXELECIDLE_O => s_rxelecidle(3),
      FABRIC_LN0_RXELECIDLE_O_H => open,
      FABRIC_LN1_RXELECIDLE_O_H => open,
      FABRIC_LN2_RXELECIDLE_O_H => open,
      FABRIC_LN3_RXELECIDLE_O_H => open,
      FABRIC_LN0_RXDET_RESULT => open,
      FABRIC_LN1_RXDET_RESULT => open,
      FABRIC_LN2_RXDET_RESULT => open,
      FABRIC_LN3_RXDET_RESULT => open,
      FABRIC_LN0_BURN_IN_TOGGLE_O => open,
      FABRIC_LN1_BURN_IN_TOGGLE_O => open,
      FABRIC_LN2_BURN_IN_TOGGLE_O => open,
      FABRIC_LN3_BURN_IN_TOGGLE_O => open,

      LANE0_ALIGN_LINK => s_align_link(0),
      LANE1_ALIGN_LINK => s_align_link(1),
      LANE2_ALIGN_LINK => s_align_link(2),
      LANE3_ALIGN_LINK => s_align_link(3),
      LANE0_K_LOCK => open,
      LANE1_K_LOCK => open,
      LANE2_K_LOCK => open,
      LANE3_K_LOCK => open,
      LANE0_DISP_ERR_O => open,
      LANE1_DISP_ERR_O => open,
      LANE2_DISP_ERR_O => open,
      LANE3_DISP_ERR_O => open,
      LANE0_DEC_ERR_O => open,
      LANE1_DEC_ERR_O => open,
      LANE2_DEC_ERR_O => open,
      LANE3_DEC_ERR_O => open,
      LANE0_CUR_DISP_O => open,
      LANE1_CUR_DISP_O => open,
      LANE2_CUR_DISP_O => open,
      LANE3_CUR_DISP_O => open,
      LANE0_ALIGN_TRIGGER => s_align_trigger(0),
      LANE1_ALIGN_TRIGGER => s_align_trigger(1),
      LANE2_ALIGN_TRIGGER => s_align_trigger(2),
      LANE3_ALIGN_TRIGGER => s_align_trigger(3),
      LANE0_CHBOND_START => s_chbond_start(0),
      LANE1_CHBOND_START => s_chbond_start(1),
      LANE2_CHBOND_START => s_chbond_start(2),
      LANE3_CHBOND_START => s_chbond_start(3),
      LANE0_PCS_TX_RST => s_pcs_tx_rst(0),
      LANE1_PCS_TX_RST => s_pcs_tx_rst(1),
      LANE2_PCS_TX_RST => s_pcs_tx_rst(2),
      LANE3_PCS_TX_RST => s_pcs_tx_rst(3),
      LANE0_PCS_RX_RST => s_pcs_rx_rst(0),
      LANE1_PCS_RX_RST => s_pcs_rx_rst(1),
      LANE2_PCS_RX_RST => s_pcs_rx_rst(2),
      LANE3_PCS_RX_RST => s_pcs_rx_rst(3),

      LANE0_PCS_TX_O_FABRIC_CLK => s_lane_pcs_tx_clk_raw(0),
      LANE1_PCS_TX_O_FABRIC_CLK => s_lane_pcs_tx_clk_raw(1),
      LANE2_PCS_TX_O_FABRIC_CLK => s_lane_pcs_tx_clk_raw(2),
      LANE3_PCS_TX_O_FABRIC_CLK => s_lane_pcs_tx_clk_raw(3),
      LANE0_PCS_RX_O_FABRIC_CLK => s_lane_pcs_rx_clk_raw(0),
      LANE1_PCS_RX_O_FABRIC_CLK => s_lane_pcs_rx_clk_raw(1),
      LANE2_PCS_RX_O_FABRIC_CLK => s_lane_pcs_rx_clk_raw(2),
      LANE3_PCS_RX_O_FABRIC_CLK => s_lane_pcs_rx_clk_raw(3),
      LANE0_FABRIC_TX_CLK => s_lane_pcs_tx_clk_buf(0),
      LANE1_FABRIC_TX_CLK => s_lane_pcs_tx_clk_buf(1),
      LANE2_FABRIC_TX_CLK => s_lane_pcs_tx_clk_buf(2),
      LANE3_FABRIC_TX_CLK => s_lane_pcs_tx_clk_buf(3),
      LANE0_FABRIC_RX_CLK => s_lane_pcs_rx_clk_buf(0),
      LANE1_FABRIC_RX_CLK => s_lane_pcs_rx_clk_buf(1),
      LANE2_FABRIC_RX_CLK => s_lane_pcs_rx_clk_buf(2),
      LANE3_FABRIC_RX_CLK => s_lane_pcs_rx_clk_buf(3),
      LANE0_FABRIC_C2I_CLK => s_lane_c2i_clk(0),
      LANE1_FABRIC_C2I_CLK => s_lane_c2i_clk(1),
      LANE2_FABRIC_C2I_CLK => s_lane_c2i_clk(2),
      LANE3_FABRIC_C2I_CLK => s_lane_c2i_clk(3),
      FABRIC_QUAD_CLK_RX => open,

      LANE0_RX_IF_FIFO_RDEN => s_rx_fifo_rden(0),
      LANE1_RX_IF_FIFO_RDEN => s_rx_fifo_rden(1),
      LANE2_RX_IF_FIFO_RDEN => s_rx_fifo_rden(2),
      LANE3_RX_IF_FIFO_RDEN => s_rx_fifo_rden(3),
      LANE0_RX_IF_FIFO_AEMPTY => s_rx_fifo_aempty(0),
      LANE1_RX_IF_FIFO_AEMPTY => s_rx_fifo_aempty(1),
      LANE2_RX_IF_FIFO_AEMPTY => s_rx_fifo_aempty(2),
      LANE3_RX_IF_FIFO_AEMPTY => s_rx_fifo_aempty(3),
      LANE0_RX_IF_FIFO_EMPTY => open,
      LANE1_RX_IF_FIFO_EMPTY => open,
      LANE2_RX_IF_FIFO_EMPTY => open,
      LANE3_RX_IF_FIFO_EMPTY => open,
      LANE0_RX_IF_FIFO_RDUSEWD => open,
      LANE1_RX_IF_FIFO_RDUSEWD => open,
      LANE2_RX_IF_FIFO_RDUSEWD => open,
      LANE3_RX_IF_FIFO_RDUSEWD => open,
      LANE0_TX_IF_FIFO_AFULL => s_tx_fifo_afull(0),
      LANE1_TX_IF_FIFO_AFULL => s_tx_fifo_afull(1),
      LANE2_TX_IF_FIFO_AFULL => s_tx_fifo_afull(2),
      LANE3_TX_IF_FIFO_AFULL => s_tx_fifo_afull(3),
      LANE0_TX_IF_FIFO_FULL => open,
      LANE1_TX_IF_FIFO_FULL => open,
      LANE2_TX_IF_FIFO_FULL => open,
      LANE3_TX_IF_FIFO_FULL => open,
      LANE0_TX_IF_FIFO_WRUSEWD => open,
      LANE1_TX_IF_FIFO_WRUSEWD => open,
      LANE2_TX_IF_FIFO_WRUSEWD => open,
      LANE3_TX_IF_FIFO_WRUSEWD => open,

      FABRIC_LANE0_64B66B_TX_INVLD_BLK => open,
      FABRIC_LANE1_64B66B_TX_INVLD_BLK => open,
      FABRIC_LANE2_64B66B_TX_INVLD_BLK => open,
      FABRIC_LANE3_64B66B_TX_INVLD_BLK => open,
      FABRIC_LANE0_64B66B_TX_FETCH => open,
      FABRIC_LANE1_64B66B_TX_FETCH => open,
      FABRIC_LANE2_64B66B_TX_FETCH => open,
      FABRIC_LANE3_64B66B_TX_FETCH => open,
      FABRIC_LANE0_64B66B_RX_VALID => open,
      FABRIC_LANE1_64B66B_RX_VALID => open,
      FABRIC_LANE2_64B66B_RX_VALID => open,
      FABRIC_LANE3_64B66B_RX_VALID => open,

      CKP_MIPI_0 => open,
      CKP_MIPI_1 => open,
      CKN_MIPI_0 => open,
      CKN_MIPI_1 => open,

      FABRIC_CLK_REF_CORE_I => "0000",
      FABRIC_CK_SOC_DIV_I => "00",
      FABRIC_BURN_IN_I => gw_gnd,
      FABRIC_GLUE_MAC_INIT_INFO_I => gw_gnd,
      FABRIC_GEARFIFO_ERR_RPT => open,
      FABRIC_CLK_MON_O => open,
      FABRIC_POR_N_I => gw_gnd,
      FABRIC_QUAD_MCU_REQ_I => gw_gnd,
      CK_AHB_I => std_logic(s_apb_clock),
      AHB_RSTN => std_logic(s_ahb_reset_n),
      TEST_DEC_EN => std_logic(s_test_dec_en),
      QUAD_PCLK0 => open,
      QUAD_PCLK1 => open,
      QUAD_PCIE_CLK => gw_gnd,
      PCIE_DIV2_REG => gw_gnd,
      PCIE_DIV4_REG => gw_gnd,
      PMAC_LN_RSTN => gw_gnd,
      CLK_VIQ_I => std_logic_vector(s_clk_viq)
      );

  -- Buffer GTR12_QUADB's life clock so it can drive the APB
  -- domain (bridge, user-facing APB master, and the primitive's
  -- own AHB clock loopback).
  apb_clock_bufg: gowin.components.bufg
    port map(
      i => s_cm_life_clk_raw,
      o => s_apb_clock
      );
  apb_clock_o <= s_apb_clock;

  upar_bridge: entity work.apb_upar_bridge_gw5a
    generic map(
      config_c => nsl_amba.apb.apb4_config(
        address_width => 24,
        data_bus_width => 32,
        strb => true,
        ready => true)
      )
    port map(
      clock_i => s_apb_clock,
      reset_n_i => apb_reset_n_i,

      apb_i => apb_m_i,
      apb_o => apb_s_o,

      ahb_reset_n_o => s_ahb_reset_n,
      test_dec_en_o => s_test_dec_en
      );

end architecture;
