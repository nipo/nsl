library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_transceiver, nsl_mii, nsl_data, nsl_io, nsl_line_coding;
use nsl_data.bytestream.all;
use nsl_io.diff.all;
use nsl_line_coding.ibm_8b10b.all;
use nsl_mii.sgmii.all;
use nsl_transceiver.lane.all;

library unisim;
use unisim.vcomponents.all;

entity sgmii_adapter is
  port(
    gt_ref_clk_pair_i : in nsl_io.diff.diff_pair;

    refclk_o : out std_ulogic;

    sgmii_i : in  sgmii_m2p;
    sgmii_o : out sgmii_p2m;

    tx_m_o : out nsl_transceiver.lane.tx_master_t;
    tx_s_i : in  nsl_transceiver.lane.tx_slave_t;
    rx_m_i : in  nsl_transceiver.lane.rx_master_t;
    rx_s_o : out nsl_transceiver.lane.rx_slave_t
    );
end entity;

architecture beh of sgmii_adapter is

  signal s_gt_ref_clk_se   : std_ulogic;
  signal s_tx2enc_symbol   : nsl_line_coding.ibm_8b10b.data_t;
  signal s_dec2rx_symbol   : nsl_line_coding.ibm_8b10b.data_t;
  signal s_code_error      : std_ulogic;
  signal s_disparity_error : std_ulogic;
  signal s_align_ready     : std_ulogic;

  -- Lanes, initialize all to null
  signal s_tx_m : nsl_transceiver.lane.tx_master_t := null_tx_master_c;
  signal s_tx_s : nsl_transceiver.lane.tx_slave_t  := null_tx_slave_c;
  signal s_rx_m : nsl_transceiver.lane.rx_master_t := null_rx_master_c;
  signal s_rx_s : nsl_transceiver.lane.rx_slave_t  := null_rx_slave_c;
  
begin

  -- IBUFDS ---------------------------------------------------------------------------
  IBUFDS_GTE2_inst : ibufds_gte2
    generic map (
      CLKCM_CFG   => TRUE,
      CLKRCV_TRST => TRUE
      )
    port map (
      O   => s_gt_ref_clk_se,
      CEB => '0',
      I   => gt_ref_clk_pair_i.p,
      IB  => gt_ref_clk_pair_i.n
      );

  refclk_o <= s_gt_ref_clk_se;

  -- Bus conversion -----------------------------------------------------------------
  s_rx_m <= rx_m_i;

  s_dec2rx_symbol.control <= rx_m_i.status(0);
  s_dec2rx_symbol.data    <= rx_m_i.data(0);
  sgmii_o.data_p2m_symbol <= s_dec2rx_symbol;
  sgmii_o.code_err        <= rx_m_i.status(2);
  sgmii_o.disparity_err   <= rx_m_i.status(1);
  sgmii_o.align_ready     <= rx_m_i.status(3);

  s_tx_m.control(0) <= sgmii_i.data_m2p_symbol.control;
  s_tx_m.data(0)    <= sgmii_i.data_m2p_symbol.data;
  s_tx_m.control(2) <= sgmii_i.sys_reset_n;
  s_tx_m.control(3) <= sgmii_i.align_rst;
  s_tx_m.control(1) <= sgmii_i.valid_symbol;

  tx_m_o <= s_tx_m;

  rx_s_o <= s_rx_s;

end architecture;
