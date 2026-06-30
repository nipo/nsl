================================
GTR12_QUADB port connection diff
================================

:Configurations sampled: 21

- ``10gbaser_refclk0_156M25_qpll0_lane0``
- ``custom_8b10b_1g_refclk0_100m_qpll0_lane0``
- ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaprx``
- ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptrx``
- ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptx``
- ``jesd204b_refclk0_100M_qpll0_lane0123``
- ``usb3_mclk_100M_qpll0_lane0``
- ``usb3_refclk0_100M_qpll0_lane0``
- ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk0_100M_qpll1_lane1``
- ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk1_125M_qpll1_lane1``
- ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_cpll_lane1``
- ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_qpll1_lane1``
- ``usb3_refclk0_100M_qpll0_lane1``
- ``usb3_refclk0_100M_qpll0_lane3``
- ``usb3_refclk0_50M_qpll0_lane0``
- ``usb3_refclk1_100M_qpll0_lane0``
- ``usb3_refclk1_100M_qpll0_lane1``
- ``usb3_refclk1_100M_qpll0_lane2``
- ``usb3_refclk1_100M_qpll0_lane3``
- ``usb3_refclk1_100M_qpll1_lane3``
- ``usb3_refin_100M_qpll0_lane0``

.. contents::
   :local:

Notation
========

- ``0`` / ``1``: single-bit tie to ``gw_gnd`` / ``gw_vcc``.
- ``0:N`` / ``1:N``: N-bit aggregate of ``gw_gnd`` / ``gw_vcc``.
- ``b<bits>``: mixed-constant aggregate, MSB-first.
- Anything else: the literal driving expression as it appears
  in ``serdes.v`` (usually a wire name like ``q0_fabric_ln0_rstn_i``).

Constant ports (235)
====================

Wizard-baked defaults: no sampled configuration changes these.
The VHDL backend can tie them to these values safely.

- ``CKN_MIPI_0`` <- ``q0_ckn_mipi_0``
- ``CKN_MIPI_1`` <- ``q0_ckn_mipi_1``
- ``CKP_MIPI_0`` <- ``q0_ckp_mipi_0``
- ``CKP_MIPI_1`` <- ``q0_ckp_mipi_1``
- ``FABRIC_BURN_IN_I`` <- ``0``
- ``FABRIC_CK_SOC_DIV_I`` <- ``0:2``
- ``FABRIC_CLK_MON_O`` <- ``q0_fabric_clk_mon_o``
- ``FABRIC_CLK_REF_CORE_I`` <- ``0:4``
- ``FABRIC_CM0_PD_REFCLK_DET_I`` <- ``0``
- ``FABRIC_CM1_LIFE_CLK_O`` <- ``q0_fabric_cm1_life_clk_o``
- ``FABRIC_CM1_PD_REFCLK_DET_I`` <- ``0``
- ``FABRIC_CM2_PD_REFCLK_DET_I`` <- ``0``
- ``FABRIC_CM3_PD_REFCLK_DET_I`` <- ``0``
- ``FABRIC_CMU0_CLK`` <- ``q0_fabric_cmu0_clk``
- ``FABRIC_CMU0_IDDQ_I`` <- ``0``
- ``FABRIC_CMU0_PD_I`` <- ``0``
- ``FABRIC_CMU0_RESETN_I`` <- ``0``
- ``FABRIC_CMU1_CK_REF_O`` <- ``q0_fabric_cmu1_ck_ref_o``
- ``FABRIC_CMU1_CLK`` <- ``q0_fabric_cmu1_clk``
- ``FABRIC_CMU1_IDDQ_I`` <- ``0``
- ``FABRIC_CMU1_OK_O`` <- ``q0_fabric_cmu1_ok_o``
- ``FABRIC_CMU1_PD_I`` <- ``0``
- ``FABRIC_CMU1_REFCLK_GATE_ACK_O`` <- ``q0_fabric_cmu1_refclk_gate_ack_o``
- ``FABRIC_CMU1_REFCLK_GATE_I`` <- ``0``
- ``FABRIC_CMU1_RESETN_I`` <- ``0``
- ``FABRIC_CMU_CK_REF_O`` <- ``q0_fabric_cmu_ck_ref_o``
- ``FABRIC_CMU_OK_O`` <- ``q0_fabric_cmu_ok_o``
- ``FABRIC_CMU_REFCLK_GATE_ACK_O`` <- ``q0_fabric_cmu_refclk_gate_ack_o``
- ``FABRIC_CMU_REFCLK_GATE_I`` <- ``0``
- ``FABRIC_CM_LIFE_CLK_O`` <- ``q0_fabric_cm_life_clk_o``
- ``FABRIC_GEARFIFO_ERR_RPT`` <- ``q0_fabric_gearfifo_err_rpt``
- ``FABRIC_GLUE_MAC_INIT_INFO_I`` <- ``0``
- ``FABRIC_LANE0_64B66B_RX_VALID`` <- ``q0_fabric_lane0_64b66b_rx_valid``
- ``FABRIC_LANE0_64B66B_TX_FETCH`` <- ``q0_fabric_lane0_64b66b_tx_fetch``
- ``FABRIC_LANE0_64B66B_TX_INVLD_BLK`` <- ``q0_fabric_lane0_64b66b_tx_invld_blk``
- ``FABRIC_LANE0_CMU_CK_REF_O`` <- ``q0_fabric_lane0_cmu_ck_ref_o``
- ``FABRIC_LANE0_CMU_OK_O`` <- ``q0_fabric_lane0_cmu_ok_o``
- ``FABRIC_LANE1_64B66B_RX_VALID`` <- ``q0_fabric_lane1_64b66b_rx_valid``
- ``FABRIC_LANE1_64B66B_TX_FETCH`` <- ``q0_fabric_lane1_64b66b_tx_fetch``
- ``FABRIC_LANE1_64B66B_TX_INVLD_BLK`` <- ``q0_fabric_lane1_64b66b_tx_invld_blk``
- ``FABRIC_LANE1_CMU_CK_REF_O`` <- ``q0_fabric_lane1_cmu_ck_ref_o``
- ``FABRIC_LANE1_CMU_OK_O`` <- ``q0_fabric_lane1_cmu_ok_o``
- ``FABRIC_LANE2_64B66B_RX_VALID`` <- ``q0_fabric_lane2_64b66b_rx_valid``
- ``FABRIC_LANE2_64B66B_TX_FETCH`` <- ``q0_fabric_lane2_64b66b_tx_fetch``
- ``FABRIC_LANE2_64B66B_TX_INVLD_BLK`` <- ``q0_fabric_lane2_64b66b_tx_invld_blk``
- ``FABRIC_LANE2_CMU_CK_REF_O`` <- ``q0_fabric_lane2_cmu_ck_ref_o``
- ``FABRIC_LANE2_CMU_OK_O`` <- ``q0_fabric_lane2_cmu_ok_o``
- ``FABRIC_LANE3_64B66B_RX_VALID`` <- ``q0_fabric_lane3_64b66b_rx_valid``
- ``FABRIC_LANE3_64B66B_TX_FETCH`` <- ``q0_fabric_lane3_64b66b_tx_fetch``
- ``FABRIC_LANE3_64B66B_TX_INVLD_BLK`` <- ``q0_fabric_lane3_64b66b_tx_invld_blk``
- ``FABRIC_LANE3_CMU_CK_REF_O`` <- ``q0_fabric_lane3_cmu_ck_ref_o``
- ``FABRIC_LANE3_CMU_OK_O`` <- ``q0_fabric_lane3_cmu_ok_o``
- ``FABRIC_LN0_ASTAT_O`` <- ``q0_fabric_ln0_astat_o``
- ``FABRIC_LN0_BURN_IN_TOGGLE_O`` <- ``q0_fabric_ln0_burn_in_toggle_o``
- ``FABRIC_LN0_CPLL_IDDQ_I`` <- ``0``
- ``FABRIC_LN0_CPLL_PD_I`` <- ``0``
- ``FABRIC_LN0_CPLL_RESETN_I`` <- ``0``
- ``FABRIC_LN0_CTRL_I`` <- ``0:43``
- ``FABRIC_LN0_CTRL_I_H`` <- ``0:43``
- ``FABRIC_LN0_IDDQ_I`` <- ``0``
- ``FABRIC_LN0_PD_I`` <- ``0:3``
- ``FABRIC_LN0_PD_I_H`` <- ``0:3``
- ``FABRIC_LN0_PMA_RX_LOCK_O`` <- ``q0_fabric_ln0_pma_rx_lock_o``
- ``FABRIC_LN0_RATE_I`` <- ``0:2``
- ``FABRIC_LN0_RATE_I_H`` <- ``0:2``
- ``FABRIC_LN0_RXDATA_O`` <- ``q0_fabric_ln0_rxdata_o``
- ``FABRIC_LN0_RXDET_RESULT`` <- ``q0_fabric_ln0_rxdet_result``
- ``FABRIC_LN0_RXELECIDLE_O`` <- ``q0_fabric_ln0_rxelecidle_o``
- ``FABRIC_LN0_RXELECIDLE_O_H`` <- ``q0_fabric_ln0_rxelecidle_o_h``
- ``FABRIC_LN0_RX_VLD_OUT`` <- ``q0_fabric_ln0_rx_vld_out``
- ``FABRIC_LN0_STAT_O`` <- ``q0_fabric_ln0_stat_o``
- ``FABRIC_LN0_STAT_O_H`` <- ``q0_fabric_ln0_stat_o_h``
- ``FABRIC_LN0_TX_DISPARITY_I`` <- ``0:8``
- ``FABRIC_LN1_ASTAT_O`` <- ``q0_fabric_ln1_astat_o``
- ``FABRIC_LN1_BURN_IN_TOGGLE_O`` <- ``q0_fabric_ln1_burn_in_toggle_o``
- ``FABRIC_LN1_CPLL_IDDQ_I`` <- ``0``
- ``FABRIC_LN1_CPLL_PD_I`` <- ``0``
- ``FABRIC_LN1_CPLL_RESETN_I`` <- ``0``
- ``FABRIC_LN1_IDDQ_I`` <- ``0``
- ``FABRIC_LN1_PD_I`` <- ``0:3``
- ``FABRIC_LN1_PD_I_H`` <- ``0:3``
- ``FABRIC_LN1_PMA_RX_LOCK_O`` <- ``q0_fabric_ln1_pma_rx_lock_o``
- ``FABRIC_LN1_RATE_I`` <- ``0:2``
- ``FABRIC_LN1_RATE_I_H`` <- ``0:2``
- ``FABRIC_LN1_RXDATA_O`` <- ``q0_fabric_ln1_rxdata_o``
- ``FABRIC_LN1_RXDET_RESULT`` <- ``q0_fabric_ln1_rxdet_result``
- ``FABRIC_LN1_RXELECIDLE_O`` <- ``q0_fabric_ln1_rxelecidle_o``
- ``FABRIC_LN1_RXELECIDLE_O_H`` <- ``q0_fabric_ln1_rxelecidle_o_h``
- ``FABRIC_LN1_RX_VLD_OUT`` <- ``q0_fabric_ln1_rx_vld_out``
- ``FABRIC_LN1_STAT_O`` <- ``q0_fabric_ln1_stat_o``
- ``FABRIC_LN1_STAT_O_H`` <- ``q0_fabric_ln1_stat_o_h``
- ``FABRIC_LN1_TX_DISPARITY_I`` <- ``0:8``
- ``FABRIC_LN2_ASTAT_O`` <- ``q0_fabric_ln2_astat_o``
- ``FABRIC_LN2_BURN_IN_TOGGLE_O`` <- ``q0_fabric_ln2_burn_in_toggle_o``
- ``FABRIC_LN2_CPLL_IDDQ_I`` <- ``0``
- ``FABRIC_LN2_CPLL_PD_I`` <- ``0``
- ``FABRIC_LN2_CPLL_RESETN_I`` <- ``0``
- ``FABRIC_LN2_CTRL_I`` <- ``0:43``
- ``FABRIC_LN2_CTRL_I_H`` <- ``0:43``
- ``FABRIC_LN2_IDDQ_I`` <- ``0``
- ``FABRIC_LN2_PD_I`` <- ``0:3``
- ``FABRIC_LN2_PD_I_H`` <- ``0:3``
- ``FABRIC_LN2_PMA_RX_LOCK_O`` <- ``q0_fabric_ln2_pma_rx_lock_o``
- ``FABRIC_LN2_RATE_I`` <- ``0:2``
- ``FABRIC_LN2_RATE_I_H`` <- ``0:2``
- ``FABRIC_LN2_RXDATA_O`` <- ``q0_fabric_ln2_rxdata_o``
- ``FABRIC_LN2_RXDET_RESULT`` <- ``q0_fabric_ln2_rxdet_result``
- ``FABRIC_LN2_RXELECIDLE_O`` <- ``q0_fabric_ln2_rxelecidle_o``
- ``FABRIC_LN2_RXELECIDLE_O_H`` <- ``q0_fabric_ln2_rxelecidle_o_h``
- ``FABRIC_LN2_RX_VLD_OUT`` <- ``q0_fabric_ln2_rx_vld_out``
- ``FABRIC_LN2_STAT_O`` <- ``q0_fabric_ln2_stat_o``
- ``FABRIC_LN2_STAT_O_H`` <- ``q0_fabric_ln2_stat_o_h``
- ``FABRIC_LN2_TX_DISPARITY_I`` <- ``0:8``
- ``FABRIC_LN3_ASTAT_O`` <- ``q0_fabric_ln3_astat_o``
- ``FABRIC_LN3_BURN_IN_TOGGLE_O`` <- ``q0_fabric_ln3_burn_in_toggle_o``
- ``FABRIC_LN3_CPLL_IDDQ_I`` <- ``0``
- ``FABRIC_LN3_CPLL_PD_I`` <- ``0``
- ``FABRIC_LN3_CPLL_RESETN_I`` <- ``0``
- ``FABRIC_LN3_CTRL_I`` <- ``0:43``
- ``FABRIC_LN3_CTRL_I_H`` <- ``0:43``
- ``FABRIC_LN3_IDDQ_I`` <- ``0``
- ``FABRIC_LN3_PD_I`` <- ``0:3``
- ``FABRIC_LN3_PD_I_H`` <- ``0:3``
- ``FABRIC_LN3_PMA_RX_LOCK_O`` <- ``q0_fabric_ln3_pma_rx_lock_o``
- ``FABRIC_LN3_RATE_I`` <- ``0:2``
- ``FABRIC_LN3_RATE_I_H`` <- ``0:2``
- ``FABRIC_LN3_RXDATA_O`` <- ``q0_fabric_ln3_rxdata_o``
- ``FABRIC_LN3_RXDET_RESULT`` <- ``q0_fabric_ln3_rxdet_result``
- ``FABRIC_LN3_RXELECIDLE_O`` <- ``q0_fabric_ln3_rxelecidle_o``
- ``FABRIC_LN3_RXELECIDLE_O_H`` <- ``q0_fabric_ln3_rxelecidle_o_h``
- ``FABRIC_LN3_RX_VLD_OUT`` <- ``q0_fabric_ln3_rx_vld_out``
- ``FABRIC_LN3_STAT_O`` <- ``q0_fabric_ln3_stat_o``
- ``FABRIC_LN3_STAT_O_H`` <- ``q0_fabric_ln3_stat_o_h``
- ``FABRIC_LN3_TX_DISPARITY_I`` <- ``0:8``
- ``FABRIC_PLL_CDN_I`` <- ``0``
- ``FABRIC_PMA_CM0_DR_REFCLK_DET_O`` <- ``q0_fabric_pma_cm0_dr_refclk_det_o``
- ``FABRIC_PMA_CM1_DR_REFCLK_DET_O`` <- ``q0_fabric_pma_cm1_dr_refclk_det_o``
- ``FABRIC_PMA_CM2_DR_REFCLK_DET_O`` <- ``q0_fabric_pma_cm2_dr_refclk_det_o``
- ``FABRIC_PMA_CM3_DR_REFCLK_DET_O`` <- ``q0_fabric_pma_cm3_dr_refclk_det_o``
- ``FABRIC_PMA_PD_REFHCLK_I`` <- ``0``
- ``FABRIC_POR_N_I`` <- ``0``
- ``FABRIC_QUAD_CLK_RX`` <- ``q0_fabric_quad_clk_rx``
- ``FABRIC_QUAD_MCU_REQ_I`` <- ``0``
- ``FABRIC_REFCLK1_INPUT_SEL_I`` <- ``0:3``
- ``FABRIC_REFCLK_GATE_ACK_O`` <- ``q0_fabric_refclk_gate_ack_o``
- ``FABRIC_REFCLK_GATE_I`` <- ``0``
- ``FABRIC_REFCLK_INPUT_SEL_I`` <- ``0:3``
- ``LANE0_ALIGN_LINK`` <- ``q0_lane0_align_link``
- ``LANE0_ALIGN_TRIGGER`` <- ``0``
- ``LANE0_CUR_DISP_O`` <- ``q0_lane0_cur_disp_o``
- ``LANE0_DEC_ERR_O`` <- ``q0_lane0_dec_err_o``
- ``LANE0_DISP_ERR_O`` <- ``q0_lane0_disp_err_o``
- ``LANE0_K_LOCK`` <- ``q0_lane0_k_lock``
- ``LANE0_PCS_RX_O_FABRIC_CLK`` <- ``q0_lane0_pcs_rx_o_fabric_clk``
- ``LANE0_PCS_TX_O_FABRIC_CLK`` <- ``q0_lane0_pcs_tx_o_fabric_clk``
- ``LANE0_RX_IF_FIFO_AEMPTY`` <- ``q0_lane0_rx_if_fifo_aempty``
- ``LANE0_RX_IF_FIFO_EMPTY`` <- ``q0_lane0_rx_if_fifo_empty``
- ``LANE0_RX_IF_FIFO_RDUSEWD`` <- ``q0_lane0_rx_if_fifo_rdusewd``
- ``LANE0_TX_IF_FIFO_AFULL`` <- ``q0_lane0_tx_if_fifo_afull``
- ``LANE0_TX_IF_FIFO_FULL`` <- ``q0_lane0_tx_if_fifo_full``
- ``LANE0_TX_IF_FIFO_WRUSEWD`` <- ``q0_lane0_tx_if_fifo_wrusewd``
- ``LANE1_ALIGN_LINK`` <- ``q0_lane1_align_link``
- ``LANE1_ALIGN_TRIGGER`` <- ``0``
- ``LANE1_CHBOND_START`` <- ``0``
- ``LANE1_CUR_DISP_O`` <- ``q0_lane1_cur_disp_o``
- ``LANE1_DEC_ERR_O`` <- ``q0_lane1_dec_err_o``
- ``LANE1_DISP_ERR_O`` <- ``q0_lane1_disp_err_o``
- ``LANE1_FABRIC_C2I_CLK`` <- ``0``
- ``LANE1_K_LOCK`` <- ``q0_lane1_k_lock``
- ``LANE1_PCS_RX_O_FABRIC_CLK`` <- ``q0_lane1_pcs_rx_o_fabric_clk``
- ``LANE1_PCS_TX_O_FABRIC_CLK`` <- ``q0_lane1_pcs_tx_o_fabric_clk``
- ``LANE1_RX_IF_FIFO_AEMPTY`` <- ``q0_lane1_rx_if_fifo_aempty``
- ``LANE1_RX_IF_FIFO_EMPTY`` <- ``q0_lane1_rx_if_fifo_empty``
- ``LANE1_RX_IF_FIFO_RDUSEWD`` <- ``q0_lane1_rx_if_fifo_rdusewd``
- ``LANE1_TX_IF_FIFO_AFULL`` <- ``q0_lane1_tx_if_fifo_afull``
- ``LANE1_TX_IF_FIFO_FULL`` <- ``q0_lane1_tx_if_fifo_full``
- ``LANE1_TX_IF_FIFO_WRUSEWD`` <- ``q0_lane1_tx_if_fifo_wrusewd``
- ``LANE2_ALIGN_LINK`` <- ``q0_lane2_align_link``
- ``LANE2_ALIGN_TRIGGER`` <- ``0``
- ``LANE2_CHBOND_START`` <- ``0``
- ``LANE2_CUR_DISP_O`` <- ``q0_lane2_cur_disp_o``
- ``LANE2_DEC_ERR_O`` <- ``q0_lane2_dec_err_o``
- ``LANE2_DISP_ERR_O`` <- ``q0_lane2_disp_err_o``
- ``LANE2_FABRIC_C2I_CLK`` <- ``0``
- ``LANE2_K_LOCK`` <- ``q0_lane2_k_lock``
- ``LANE2_PCS_RX_O_FABRIC_CLK`` <- ``q0_lane2_pcs_rx_o_fabric_clk``
- ``LANE2_PCS_TX_O_FABRIC_CLK`` <- ``q0_lane2_pcs_tx_o_fabric_clk``
- ``LANE2_RX_IF_FIFO_AEMPTY`` <- ``q0_lane2_rx_if_fifo_aempty``
- ``LANE2_RX_IF_FIFO_EMPTY`` <- ``q0_lane2_rx_if_fifo_empty``
- ``LANE2_RX_IF_FIFO_RDUSEWD`` <- ``q0_lane2_rx_if_fifo_rdusewd``
- ``LANE2_TX_IF_FIFO_AFULL`` <- ``q0_lane2_tx_if_fifo_afull``
- ``LANE2_TX_IF_FIFO_FULL`` <- ``q0_lane2_tx_if_fifo_full``
- ``LANE2_TX_IF_FIFO_WRUSEWD`` <- ``q0_lane2_tx_if_fifo_wrusewd``
- ``LANE3_ALIGN_LINK`` <- ``q0_lane3_align_link``
- ``LANE3_ALIGN_TRIGGER`` <- ``0``
- ``LANE3_CHBOND_START`` <- ``0``
- ``LANE3_CUR_DISP_O`` <- ``q0_lane3_cur_disp_o``
- ``LANE3_DEC_ERR_O`` <- ``q0_lane3_dec_err_o``
- ``LANE3_DISP_ERR_O`` <- ``q0_lane3_disp_err_o``
- ``LANE3_FABRIC_C2I_CLK`` <- ``0``
- ``LANE3_K_LOCK`` <- ``q0_lane3_k_lock``
- ``LANE3_PCS_RX_O_FABRIC_CLK`` <- ``q0_lane3_pcs_rx_o_fabric_clk``
- ``LANE3_PCS_TX_O_FABRIC_CLK`` <- ``q0_lane3_pcs_tx_o_fabric_clk``
- ``LANE3_RX_IF_FIFO_AEMPTY`` <- ``q0_lane3_rx_if_fifo_aempty``
- ``LANE3_RX_IF_FIFO_EMPTY`` <- ``q0_lane3_rx_if_fifo_empty``
- ``LANE3_RX_IF_FIFO_RDUSEWD`` <- ``q0_lane3_rx_if_fifo_rdusewd``
- ``LANE3_TX_IF_FIFO_AFULL`` <- ``q0_lane3_tx_if_fifo_afull``
- ``LANE3_TX_IF_FIFO_FULL`` <- ``q0_lane3_tx_if_fifo_full``
- ``LANE3_TX_IF_FIFO_WRUSEWD`` <- ``q0_lane3_tx_if_fifo_wrusewd``
- ``LN0_RXM_I`` <- ``0``
- ``LN0_RXP_I`` <- ``0``
- ``LN0_TXM_O`` <- ``q0_ln0_txm_o``
- ``LN0_TXP_O`` <- ``q0_ln0_txp_o``
- ``LN1_RXM_I`` <- ``0``
- ``LN1_RXP_I`` <- ``0``
- ``LN1_TXM_O`` <- ``q0_ln1_txm_o``
- ``LN1_TXP_O`` <- ``q0_ln1_txp_o``
- ``LN2_RXM_I`` <- ``0``
- ``LN2_RXP_I`` <- ``0``
- ``LN2_TXM_O`` <- ``q0_ln2_txm_o``
- ``LN2_TXP_O`` <- ``q0_ln2_txp_o``
- ``LN3_RXM_I`` <- ``0``
- ``LN3_RXP_I`` <- ``0``
- ``LN3_TXM_O`` <- ``q0_ln3_txm_o``
- ``LN3_TXP_O`` <- ``q0_ln3_txp_o``
- ``PCIE_DIV2_REG`` <- ``0``
- ``PCIE_DIV4_REG`` <- ``0``
- ``PMAC_LN_RSTN`` <- ``0``
- ``QUAD_PCIE_CLK`` <- ``0``
- ``QUAD_PCLK0`` <- ``q0_quad_pclk0``
- ``QUAD_PCLK1`` <- ``q0_quad_pclk1``
- ``REFCLKM0_I`` <- ``0``
- ``REFCLKM1_I`` <- ``0``
- ``REFCLKP0_I`` <- ``0``
- ``REFCLKP1_I`` <- ``0``

Varying ports (40)
==================

``AHB_RSTN``
------------

- ``0``:

  - ``10gbaser_refclk0_156M25_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaprx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptrx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptx``

  - ``jesd204b_refclk0_100M_qpll0_lane0123``
- ``ahb_rstn_o``:

  - ``usb3_mclk_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk0_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk1_125M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_cpll_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane1``

  - ``usb3_refclk0_100M_qpll0_lane3``

  - ``usb3_refclk0_50M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane1``

  - ``usb3_refclk1_100M_qpll0_lane2``

  - ``usb3_refclk1_100M_qpll0_lane3``

  - ``usb3_refclk1_100M_qpll1_lane3``

  - ``usb3_refin_100M_qpll0_lane0``

``CK_AHB_I``
------------

- ``0``:

  - ``10gbaser_refclk0_156M25_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaprx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptrx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptx``

  - ``jesd204b_refclk0_100M_qpll0_lane0123``
- ``q0_fabric_cm_life_clk_o``:

  - ``usb3_mclk_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk0_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk1_125M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_cpll_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane1``

  - ``usb3_refclk0_100M_qpll0_lane3``

  - ``usb3_refclk0_50M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane1``

  - ``usb3_refclk1_100M_qpll0_lane2``

  - ``usb3_refclk1_100M_qpll0_lane3``

  - ``usb3_refclk1_100M_qpll1_lane3``

  - ``usb3_refin_100M_qpll0_lane0``

``CLK_VIQ_I``
-------------

- ``0:2``:

  - ``10gbaser_refclk0_156M25_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaprx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptrx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptx``

  - ``jesd204b_refclk0_100M_qpll0_lane0123``

  - ``usb3_refclk0_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk0_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk1_125M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_cpll_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane1``

  - ``usb3_refclk0_100M_qpll0_lane3``

  - ``usb3_refclk0_50M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane1``

  - ``usb3_refclk1_100M_qpll0_lane2``

  - ``usb3_refclk1_100M_qpll0_lane3``

  - ``usb3_refclk1_100M_qpll1_lane3``
- ``{gw_gnd,gpio_refclk_i}``:

  - ``usb3_refin_100M_qpll0_lane0``
- ``{mclk_i,gw_gnd}``:

  - ``usb3_mclk_100M_qpll0_lane0``

``FABRIC_LN0_RSTN_I``
---------------------

- ``0``:

  - ``usb3_refclk0_100M_qpll0_lane1``

  - ``usb3_refclk0_100M_qpll0_lane3``

  - ``usb3_refclk1_100M_qpll0_lane1``

  - ``usb3_refclk1_100M_qpll0_lane2``

  - ``usb3_refclk1_100M_qpll0_lane3``

  - ``usb3_refclk1_100M_qpll1_lane3``
- ``q0_fabric_ln0_rstn_i``:

  - ``10gbaser_refclk0_156M25_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaprx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptrx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptx``

  - ``usb3_mclk_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk0_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk1_125M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_cpll_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_qpll1_lane1``

  - ``usb3_refclk0_50M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane0``

  - ``usb3_refin_100M_qpll0_lane0``
- ``q0_fabric_ln3_rstn_i``:

  - ``jesd204b_refclk0_100M_qpll0_lane0123``

``FABRIC_LN0_TXDATA_I``
-----------------------

- ``0:80``:

  - ``jesd204b_refclk0_100M_qpll0_lane0123``

  - ``usb3_refclk0_100M_qpll0_lane1``

  - ``usb3_refclk0_100M_qpll0_lane3``

  - ``usb3_refclk1_100M_qpll0_lane1``

  - ``usb3_refclk1_100M_qpll0_lane2``

  - ``usb3_refclk1_100M_qpll0_lane3``

  - ``usb3_refclk1_100M_qpll1_lane3``
- ``q0_fabric_ln0_txdata_i``:

  - ``10gbaser_refclk0_156M25_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaprx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptrx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptx``

  - ``usb3_mclk_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk0_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk1_125M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_cpll_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_qpll1_lane1``

  - ``usb3_refclk0_50M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane0``

  - ``usb3_refin_100M_qpll0_lane0``

``FABRIC_LN0_TX_VLD_IN``
------------------------

- ``0``:

  - ``jesd204b_refclk0_100M_qpll0_lane0123``

  - ``usb3_refclk0_100M_qpll0_lane1``

  - ``usb3_refclk0_100M_qpll0_lane3``

  - ``usb3_refclk1_100M_qpll0_lane1``

  - ``usb3_refclk1_100M_qpll0_lane2``

  - ``usb3_refclk1_100M_qpll0_lane3``

  - ``usb3_refclk1_100M_qpll1_lane3``
- ``q0_fabric_ln0_tx_vld_in``:

  - ``10gbaser_refclk0_156M25_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaprx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptrx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptx``

  - ``usb3_mclk_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk0_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk1_125M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_cpll_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_qpll1_lane1``

  - ``usb3_refclk0_50M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane0``

  - ``usb3_refin_100M_qpll0_lane0``

``FABRIC_LN1_CTRL_I``
---------------------

- ``0:43``:

  - ``10gbaser_refclk0_156M25_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaprx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptrx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptx``

  - ``jesd204b_refclk0_100M_qpll0_lane0123``

  - ``usb3_mclk_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_cpll_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane1``

  - ``usb3_refclk0_100M_qpll0_lane3``

  - ``usb3_refclk0_50M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane1``

  - ``usb3_refclk1_100M_qpll0_lane2``

  - ``usb3_refclk1_100M_qpll0_lane3``

  - ``usb3_refclk1_100M_qpll1_lane3``

  - ``usb3_refin_100M_qpll0_lane0``
- ``q0_fabric_ln1_ctrl_i``:

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk0_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk1_125M_qpll1_lane1``

``FABRIC_LN1_CTRL_I_H``
-----------------------

- ``0:43``:

  - ``10gbaser_refclk0_156M25_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaprx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptrx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptx``

  - ``jesd204b_refclk0_100M_qpll0_lane0123``

  - ``usb3_mclk_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_cpll_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane1``

  - ``usb3_refclk0_100M_qpll0_lane3``

  - ``usb3_refclk0_50M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane1``

  - ``usb3_refclk1_100M_qpll0_lane2``

  - ``usb3_refclk1_100M_qpll0_lane3``

  - ``usb3_refclk1_100M_qpll1_lane3``

  - ``usb3_refin_100M_qpll0_lane0``
- ``q0_fabric_ln1_ctrl_i_h``:

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk0_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk1_125M_qpll1_lane1``

``FABRIC_LN1_RSTN_I``
---------------------

- ``0``:

  - ``10gbaser_refclk0_156M25_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaprx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptrx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptx``

  - ``usb3_mclk_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane3``

  - ``usb3_refclk0_50M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane2``

  - ``usb3_refclk1_100M_qpll0_lane3``

  - ``usb3_refclk1_100M_qpll1_lane3``

  - ``usb3_refin_100M_qpll0_lane0``
- ``q0_fabric_ln1_rstn_i``:

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk0_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk1_125M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_cpll_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane1``

  - ``usb3_refclk1_100M_qpll0_lane1``
- ``q0_fabric_ln3_rstn_i``:

  - ``jesd204b_refclk0_100M_qpll0_lane0123``

``FABRIC_LN1_TXDATA_I``
-----------------------

- ``0:80``:

  - ``10gbaser_refclk0_156M25_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaprx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptrx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptx``

  - ``jesd204b_refclk0_100M_qpll0_lane0123``

  - ``usb3_mclk_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane3``

  - ``usb3_refclk0_50M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane2``

  - ``usb3_refclk1_100M_qpll0_lane3``

  - ``usb3_refclk1_100M_qpll1_lane3``

  - ``usb3_refin_100M_qpll0_lane0``
- ``q0_fabric_ln1_txdata_i``:

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk0_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk1_125M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_cpll_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane1``

  - ``usb3_refclk1_100M_qpll0_lane1``

``FABRIC_LN1_TX_VLD_IN``
------------------------

- ``0``:

  - ``10gbaser_refclk0_156M25_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaprx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptrx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptx``

  - ``jesd204b_refclk0_100M_qpll0_lane0123``

  - ``usb3_mclk_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane3``

  - ``usb3_refclk0_50M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane2``

  - ``usb3_refclk1_100M_qpll0_lane3``

  - ``usb3_refclk1_100M_qpll1_lane3``

  - ``usb3_refin_100M_qpll0_lane0``
- ``q0_fabric_ln1_tx_vld_in``:

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk0_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk1_125M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_cpll_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane1``

  - ``usb3_refclk1_100M_qpll0_lane1``

``FABRIC_LN2_RSTN_I``
---------------------

- ``0``:

  - ``10gbaser_refclk0_156M25_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaprx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptrx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptx``

  - ``usb3_mclk_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk0_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk1_125M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_cpll_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane1``

  - ``usb3_refclk0_100M_qpll0_lane3``

  - ``usb3_refclk0_50M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane1``

  - ``usb3_refclk1_100M_qpll0_lane3``

  - ``usb3_refclk1_100M_qpll1_lane3``

  - ``usb3_refin_100M_qpll0_lane0``
- ``q0_fabric_ln2_rstn_i``:

  - ``usb3_refclk1_100M_qpll0_lane2``
- ``q0_fabric_ln3_rstn_i``:

  - ``jesd204b_refclk0_100M_qpll0_lane0123``

``FABRIC_LN2_TXDATA_I``
-----------------------

- ``0:80``:

  - ``10gbaser_refclk0_156M25_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaprx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptrx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptx``

  - ``jesd204b_refclk0_100M_qpll0_lane0123``

  - ``usb3_mclk_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk0_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk1_125M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_cpll_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane1``

  - ``usb3_refclk0_100M_qpll0_lane3``

  - ``usb3_refclk0_50M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane1``

  - ``usb3_refclk1_100M_qpll0_lane3``

  - ``usb3_refclk1_100M_qpll1_lane3``

  - ``usb3_refin_100M_qpll0_lane0``
- ``q0_fabric_ln2_txdata_i``:

  - ``usb3_refclk1_100M_qpll0_lane2``

``FABRIC_LN2_TX_VLD_IN``
------------------------

- ``0``:

  - ``10gbaser_refclk0_156M25_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaprx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptrx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptx``

  - ``jesd204b_refclk0_100M_qpll0_lane0123``

  - ``usb3_mclk_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk0_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk1_125M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_cpll_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane1``

  - ``usb3_refclk0_100M_qpll0_lane3``

  - ``usb3_refclk0_50M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane1``

  - ``usb3_refclk1_100M_qpll0_lane3``

  - ``usb3_refclk1_100M_qpll1_lane3``

  - ``usb3_refin_100M_qpll0_lane0``
- ``q0_fabric_ln2_tx_vld_in``:

  - ``usb3_refclk1_100M_qpll0_lane2``

``FABRIC_LN3_RSTN_I``
---------------------

- ``0``:

  - ``10gbaser_refclk0_156M25_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaprx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptrx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptx``

  - ``usb3_mclk_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk0_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk1_125M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_cpll_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane1``

  - ``usb3_refclk0_50M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane1``

  - ``usb3_refclk1_100M_qpll0_lane2``

  - ``usb3_refin_100M_qpll0_lane0``
- ``q0_fabric_ln3_rstn_i``:

  - ``jesd204b_refclk0_100M_qpll0_lane0123``

  - ``usb3_refclk0_100M_qpll0_lane3``

  - ``usb3_refclk1_100M_qpll0_lane3``

  - ``usb3_refclk1_100M_qpll1_lane3``

``FABRIC_LN3_TXDATA_I``
-----------------------

- ``0:80``:

  - ``10gbaser_refclk0_156M25_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaprx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptrx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptx``

  - ``jesd204b_refclk0_100M_qpll0_lane0123``

  - ``usb3_mclk_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk0_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk1_125M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_cpll_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane1``

  - ``usb3_refclk0_50M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane1``

  - ``usb3_refclk1_100M_qpll0_lane2``

  - ``usb3_refin_100M_qpll0_lane0``
- ``q0_fabric_ln3_txdata_i``:

  - ``usb3_refclk0_100M_qpll0_lane3``

  - ``usb3_refclk1_100M_qpll0_lane3``

  - ``usb3_refclk1_100M_qpll1_lane3``

``FABRIC_LN3_TX_VLD_IN``
------------------------

- ``0``:

  - ``10gbaser_refclk0_156M25_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaprx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptrx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptx``

  - ``jesd204b_refclk0_100M_qpll0_lane0123``

  - ``usb3_mclk_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk0_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk1_125M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_cpll_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane1``

  - ``usb3_refclk0_50M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane1``

  - ``usb3_refclk1_100M_qpll0_lane2``

  - ``usb3_refin_100M_qpll0_lane0``
- ``q0_fabric_ln3_tx_vld_in``:

  - ``usb3_refclk0_100M_qpll0_lane3``

  - ``usb3_refclk1_100M_qpll0_lane3``

  - ``usb3_refclk1_100M_qpll1_lane3``

``LANE0_CHBOND_START``
----------------------

- ``0``:

  - ``10gbaser_refclk0_156M25_qpll0_lane0``

  - ``jesd204b_refclk0_100M_qpll0_lane0123``

  - ``usb3_mclk_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk0_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk1_125M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_cpll_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane1``

  - ``usb3_refclk0_100M_qpll0_lane3``

  - ``usb3_refclk0_50M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane1``

  - ``usb3_refclk1_100M_qpll0_lane2``

  - ``usb3_refclk1_100M_qpll0_lane3``

  - ``usb3_refclk1_100M_qpll1_lane3``

  - ``usb3_refin_100M_qpll0_lane0``
- ``q0_lane0_chbond_start``:

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaprx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptrx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptx``

``LANE0_FABRIC_C2I_CLK``
------------------------

- ``0``:

  - ``10gbaser_refclk0_156M25_qpll0_lane0``

  - ``jesd204b_refclk0_100M_qpll0_lane0123``

  - ``usb3_mclk_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk0_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk1_125M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_cpll_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane1``

  - ``usb3_refclk0_100M_qpll0_lane3``

  - ``usb3_refclk0_50M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane1``

  - ``usb3_refclk1_100M_qpll0_lane2``

  - ``usb3_refclk1_100M_qpll0_lane3``

  - ``usb3_refclk1_100M_qpll1_lane3``

  - ``usb3_refin_100M_qpll0_lane0``
- ``q0_lane0_fabric_c2i_clk``:

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaprx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptrx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptx``

``LANE0_FABRIC_RX_CLK``
-----------------------

- ``0``:

  - ``usb3_refclk0_100M_qpll0_lane1``

  - ``usb3_refclk0_100M_qpll0_lane3``

  - ``usb3_refclk1_100M_qpll0_lane1``

  - ``usb3_refclk1_100M_qpll0_lane2``

  - ``usb3_refclk1_100M_qpll0_lane3``

  - ``usb3_refclk1_100M_qpll1_lane3``
- ``q0_lane0_fabric_rx_clk``:

  - ``10gbaser_refclk0_156M25_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaprx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptrx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptx``

  - ``usb3_mclk_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk0_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk1_125M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_cpll_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_qpll1_lane1``

  - ``usb3_refclk0_50M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane0``

  - ``usb3_refin_100M_qpll0_lane0``
- ``q0_lane3_fabric_rx_clk``:

  - ``jesd204b_refclk0_100M_qpll0_lane0123``

``LANE0_FABRIC_TX_CLK``
-----------------------

- ``0``:

  - ``jesd204b_refclk0_100M_qpll0_lane0123``

  - ``usb3_refclk0_100M_qpll0_lane1``

  - ``usb3_refclk0_100M_qpll0_lane3``

  - ``usb3_refclk1_100M_qpll0_lane1``

  - ``usb3_refclk1_100M_qpll0_lane2``

  - ``usb3_refclk1_100M_qpll0_lane3``

  - ``usb3_refclk1_100M_qpll1_lane3``
- ``q0_lane0_fabric_tx_clk``:

  - ``10gbaser_refclk0_156M25_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaprx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptrx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptx``

  - ``usb3_mclk_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk0_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk1_125M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_cpll_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_qpll1_lane1``

  - ``usb3_refclk0_50M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane0``

  - ``usb3_refin_100M_qpll0_lane0``

``LANE0_PCS_RX_RST``
--------------------

- ``0``:

  - ``usb3_refclk0_100M_qpll0_lane1``

  - ``usb3_refclk0_100M_qpll0_lane3``

  - ``usb3_refclk1_100M_qpll0_lane1``

  - ``usb3_refclk1_100M_qpll0_lane2``

  - ``usb3_refclk1_100M_qpll0_lane3``

  - ``usb3_refclk1_100M_qpll1_lane3``
- ``q0_lane0_pcs_rx_rst``:

  - ``10gbaser_refclk0_156M25_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaprx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptrx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptx``

  - ``usb3_mclk_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk0_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk1_125M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_cpll_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_qpll1_lane1``

  - ``usb3_refclk0_50M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane0``

  - ``usb3_refin_100M_qpll0_lane0``
- ``q0_lane3_pcs_rx_rst``:

  - ``jesd204b_refclk0_100M_qpll0_lane0123``

``LANE0_PCS_TX_RST``
--------------------

- ``0``:

  - ``jesd204b_refclk0_100M_qpll0_lane0123``

  - ``usb3_refclk0_100M_qpll0_lane1``

  - ``usb3_refclk0_100M_qpll0_lane3``

  - ``usb3_refclk1_100M_qpll0_lane1``

  - ``usb3_refclk1_100M_qpll0_lane2``

  - ``usb3_refclk1_100M_qpll0_lane3``

  - ``usb3_refclk1_100M_qpll1_lane3``
- ``q0_lane0_pcs_tx_rst``:

  - ``10gbaser_refclk0_156M25_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaprx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptrx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptx``

  - ``usb3_mclk_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk0_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk1_125M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_cpll_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_qpll1_lane1``

  - ``usb3_refclk0_50M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane0``

  - ``usb3_refin_100M_qpll0_lane0``

``LANE0_RX_IF_FIFO_RDEN``
-------------------------

- ``0``:

  - ``usb3_refclk0_100M_qpll0_lane1``

  - ``usb3_refclk0_100M_qpll0_lane3``

  - ``usb3_refclk1_100M_qpll0_lane1``

  - ``usb3_refclk1_100M_qpll0_lane2``

  - ``usb3_refclk1_100M_qpll0_lane3``

  - ``usb3_refclk1_100M_qpll1_lane3``
- ``q0_lane0_rx_if_fifo_rden``:

  - ``10gbaser_refclk0_156M25_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaprx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptrx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptx``

  - ``jesd204b_refclk0_100M_qpll0_lane0123``

  - ``usb3_mclk_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk0_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk1_125M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_cpll_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_qpll1_lane1``

  - ``usb3_refclk0_50M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane0``

  - ``usb3_refin_100M_qpll0_lane0``

``LANE1_FABRIC_RX_CLK``
-----------------------

- ``0``:

  - ``10gbaser_refclk0_156M25_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaprx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptrx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptx``

  - ``usb3_mclk_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane3``

  - ``usb3_refclk0_50M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane2``

  - ``usb3_refclk1_100M_qpll0_lane3``

  - ``usb3_refclk1_100M_qpll1_lane3``

  - ``usb3_refin_100M_qpll0_lane0``
- ``q0_lane1_fabric_rx_clk``:

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk0_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk1_125M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_cpll_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane1``

  - ``usb3_refclk1_100M_qpll0_lane1``
- ``q0_lane3_fabric_rx_clk``:

  - ``jesd204b_refclk0_100M_qpll0_lane0123``

``LANE1_FABRIC_TX_CLK``
-----------------------

- ``0``:

  - ``10gbaser_refclk0_156M25_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaprx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptrx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptx``

  - ``jesd204b_refclk0_100M_qpll0_lane0123``

  - ``usb3_mclk_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane3``

  - ``usb3_refclk0_50M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane2``

  - ``usb3_refclk1_100M_qpll0_lane3``

  - ``usb3_refclk1_100M_qpll1_lane3``

  - ``usb3_refin_100M_qpll0_lane0``
- ``q0_lane1_fabric_tx_clk``:

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk0_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk1_125M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_cpll_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane1``

  - ``usb3_refclk1_100M_qpll0_lane1``

``LANE1_PCS_RX_RST``
--------------------

- ``0``:

  - ``10gbaser_refclk0_156M25_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaprx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptrx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptx``

  - ``usb3_mclk_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane3``

  - ``usb3_refclk0_50M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane2``

  - ``usb3_refclk1_100M_qpll0_lane3``

  - ``usb3_refclk1_100M_qpll1_lane3``

  - ``usb3_refin_100M_qpll0_lane0``
- ``q0_lane1_pcs_rx_rst``:

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk0_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk1_125M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_cpll_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane1``

  - ``usb3_refclk1_100M_qpll0_lane1``
- ``q0_lane3_pcs_rx_rst``:

  - ``jesd204b_refclk0_100M_qpll0_lane0123``

``LANE1_PCS_TX_RST``
--------------------

- ``0``:

  - ``10gbaser_refclk0_156M25_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaprx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptrx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptx``

  - ``jesd204b_refclk0_100M_qpll0_lane0123``

  - ``usb3_mclk_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane3``

  - ``usb3_refclk0_50M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane2``

  - ``usb3_refclk1_100M_qpll0_lane3``

  - ``usb3_refclk1_100M_qpll1_lane3``

  - ``usb3_refin_100M_qpll0_lane0``
- ``q0_lane1_pcs_tx_rst``:

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk0_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk1_125M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_cpll_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane1``

  - ``usb3_refclk1_100M_qpll0_lane1``

``LANE1_RX_IF_FIFO_RDEN``
-------------------------

- ``0``:

  - ``10gbaser_refclk0_156M25_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaprx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptrx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptx``

  - ``usb3_mclk_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane3``

  - ``usb3_refclk0_50M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane2``

  - ``usb3_refclk1_100M_qpll0_lane3``

  - ``usb3_refclk1_100M_qpll1_lane3``

  - ``usb3_refin_100M_qpll0_lane0``
- ``q0_lane1_rx_if_fifo_rden``:

  - ``jesd204b_refclk0_100M_qpll0_lane0123``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk0_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk1_125M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_cpll_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane1``

  - ``usb3_refclk1_100M_qpll0_lane1``

``LANE2_FABRIC_RX_CLK``
-----------------------

- ``0``:

  - ``10gbaser_refclk0_156M25_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaprx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptrx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptx``

  - ``usb3_mclk_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk0_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk1_125M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_cpll_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane1``

  - ``usb3_refclk0_100M_qpll0_lane3``

  - ``usb3_refclk0_50M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane1``

  - ``usb3_refclk1_100M_qpll0_lane3``

  - ``usb3_refclk1_100M_qpll1_lane3``

  - ``usb3_refin_100M_qpll0_lane0``
- ``q0_lane2_fabric_rx_clk``:

  - ``usb3_refclk1_100M_qpll0_lane2``
- ``q0_lane3_fabric_rx_clk``:

  - ``jesd204b_refclk0_100M_qpll0_lane0123``

``LANE2_FABRIC_TX_CLK``
-----------------------

- ``0``:

  - ``10gbaser_refclk0_156M25_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaprx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptrx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptx``

  - ``jesd204b_refclk0_100M_qpll0_lane0123``

  - ``usb3_mclk_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk0_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk1_125M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_cpll_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane1``

  - ``usb3_refclk0_100M_qpll0_lane3``

  - ``usb3_refclk0_50M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane1``

  - ``usb3_refclk1_100M_qpll0_lane3``

  - ``usb3_refclk1_100M_qpll1_lane3``

  - ``usb3_refin_100M_qpll0_lane0``
- ``q0_lane2_fabric_tx_clk``:

  - ``usb3_refclk1_100M_qpll0_lane2``

``LANE2_PCS_RX_RST``
--------------------

- ``0``:

  - ``10gbaser_refclk0_156M25_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaprx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptrx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptx``

  - ``usb3_mclk_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk0_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk1_125M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_cpll_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane1``

  - ``usb3_refclk0_100M_qpll0_lane3``

  - ``usb3_refclk0_50M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane1``

  - ``usb3_refclk1_100M_qpll0_lane3``

  - ``usb3_refclk1_100M_qpll1_lane3``

  - ``usb3_refin_100M_qpll0_lane0``
- ``q0_lane2_pcs_rx_rst``:

  - ``usb3_refclk1_100M_qpll0_lane2``
- ``q0_lane3_pcs_rx_rst``:

  - ``jesd204b_refclk0_100M_qpll0_lane0123``

``LANE2_PCS_TX_RST``
--------------------

- ``0``:

  - ``10gbaser_refclk0_156M25_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaprx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptrx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptx``

  - ``jesd204b_refclk0_100M_qpll0_lane0123``

  - ``usb3_mclk_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk0_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk1_125M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_cpll_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane1``

  - ``usb3_refclk0_100M_qpll0_lane3``

  - ``usb3_refclk0_50M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane1``

  - ``usb3_refclk1_100M_qpll0_lane3``

  - ``usb3_refclk1_100M_qpll1_lane3``

  - ``usb3_refin_100M_qpll0_lane0``
- ``q0_lane2_pcs_tx_rst``:

  - ``usb3_refclk1_100M_qpll0_lane2``

``LANE2_RX_IF_FIFO_RDEN``
-------------------------

- ``0``:

  - ``10gbaser_refclk0_156M25_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaprx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptrx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptx``

  - ``usb3_mclk_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk0_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk1_125M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_cpll_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane1``

  - ``usb3_refclk0_100M_qpll0_lane3``

  - ``usb3_refclk0_50M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane1``

  - ``usb3_refclk1_100M_qpll0_lane3``

  - ``usb3_refclk1_100M_qpll1_lane3``

  - ``usb3_refin_100M_qpll0_lane0``
- ``q0_lane2_rx_if_fifo_rden``:

  - ``jesd204b_refclk0_100M_qpll0_lane0123``

  - ``usb3_refclk1_100M_qpll0_lane2``

``LANE3_FABRIC_RX_CLK``
-----------------------

- ``0``:

  - ``10gbaser_refclk0_156M25_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaprx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptrx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptx``

  - ``usb3_mclk_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk0_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk1_125M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_cpll_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane1``

  - ``usb3_refclk0_50M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane1``

  - ``usb3_refclk1_100M_qpll0_lane2``

  - ``usb3_refin_100M_qpll0_lane0``
- ``q0_lane3_fabric_rx_clk``:

  - ``jesd204b_refclk0_100M_qpll0_lane0123``

  - ``usb3_refclk0_100M_qpll0_lane3``

  - ``usb3_refclk1_100M_qpll0_lane3``

  - ``usb3_refclk1_100M_qpll1_lane3``

``LANE3_FABRIC_TX_CLK``
-----------------------

- ``0``:

  - ``10gbaser_refclk0_156M25_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaprx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptrx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptx``

  - ``jesd204b_refclk0_100M_qpll0_lane0123``

  - ``usb3_mclk_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk0_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk1_125M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_cpll_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane1``

  - ``usb3_refclk0_50M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane1``

  - ``usb3_refclk1_100M_qpll0_lane2``

  - ``usb3_refin_100M_qpll0_lane0``
- ``q0_lane3_fabric_tx_clk``:

  - ``usb3_refclk0_100M_qpll0_lane3``

  - ``usb3_refclk1_100M_qpll0_lane3``

  - ``usb3_refclk1_100M_qpll1_lane3``

``LANE3_PCS_RX_RST``
--------------------

- ``0``:

  - ``10gbaser_refclk0_156M25_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaprx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptrx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptx``

  - ``usb3_mclk_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk0_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk1_125M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_cpll_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane1``

  - ``usb3_refclk0_50M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane1``

  - ``usb3_refclk1_100M_qpll0_lane2``

  - ``usb3_refin_100M_qpll0_lane0``
- ``q0_lane3_pcs_rx_rst``:

  - ``jesd204b_refclk0_100M_qpll0_lane0123``

  - ``usb3_refclk0_100M_qpll0_lane3``

  - ``usb3_refclk1_100M_qpll0_lane3``

  - ``usb3_refclk1_100M_qpll1_lane3``

``LANE3_PCS_TX_RST``
--------------------

- ``0``:

  - ``10gbaser_refclk0_156M25_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaprx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptrx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptx``

  - ``jesd204b_refclk0_100M_qpll0_lane0123``

  - ``usb3_mclk_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk0_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk1_125M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_cpll_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane1``

  - ``usb3_refclk0_50M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane1``

  - ``usb3_refclk1_100M_qpll0_lane2``

  - ``usb3_refin_100M_qpll0_lane0``
- ``q0_lane3_pcs_tx_rst``:

  - ``usb3_refclk0_100M_qpll0_lane3``

  - ``usb3_refclk1_100M_qpll0_lane3``

  - ``usb3_refclk1_100M_qpll1_lane3``

``LANE3_RX_IF_FIFO_RDEN``
-------------------------

- ``0``:

  - ``10gbaser_refclk0_156M25_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaprx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptrx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptx``

  - ``usb3_mclk_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk0_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk1_125M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_cpll_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane1``

  - ``usb3_refclk0_50M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane1``

  - ``usb3_refclk1_100M_qpll0_lane2``

  - ``usb3_refin_100M_qpll0_lane0``
- ``q0_lane3_rx_if_fifo_rden``:

  - ``jesd204b_refclk0_100M_qpll0_lane0123``

  - ``usb3_refclk0_100M_qpll0_lane3``

  - ``usb3_refclk1_100M_qpll0_lane3``

  - ``usb3_refclk1_100M_qpll1_lane3``

``TEST_DEC_EN``
---------------

- ``0``:

  - ``10gbaser_refclk0_156M25_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaprx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptrx``

  - ``custom_8b10b_1g_refclk0_100m_qpll0_lane0_swaptx``

  - ``jesd204b_refclk0_100M_qpll0_lane0123``
- ``quad_cfg_test_dec_en``:

  - ``usb3_mclk_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk0_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__1000basex_refclk1_125M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_cpll_lane1``

  - ``usb3_refclk0_100M_qpll0_lane0__usb3_refclk1_100M_qpll1_lane1``

  - ``usb3_refclk0_100M_qpll0_lane1``

  - ``usb3_refclk0_100M_qpll0_lane3``

  - ``usb3_refclk0_50M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane0``

  - ``usb3_refclk1_100M_qpll0_lane1``

  - ``usb3_refclk1_100M_qpll0_lane2``

  - ``usb3_refclk1_100M_qpll0_lane3``

  - ``usb3_refclk1_100M_qpll1_lane3``

  - ``usb3_refin_100M_qpll0_lane0``

