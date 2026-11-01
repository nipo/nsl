library ieee;
use ieee.std_logic_1164.all;

library nsl_transceiver, nsl_mii;
use nsl_mii.sgmii.all;

-- Translates between the SGMII PCS symbol interface (sgmii_m2p_t / sgmii_p2m_t)
-- and the lanes of a transceiver_cluster (8B10B, data_byte_count = 1).
--
-- One adapter serves any number of lanes: lane i of every port is wired to
-- lane i of the others. All five vectors must have the same length; they do
-- not need to share the same index range (0 to n-1 is the usual one).
--
-- The lane carries one byte per cycle, and the sideband of that byte
-- follows the ENCODING_8B10B layout of nsl_transceiver.lane. The PCS
-- drives the running disparity of every code group it emits, so the
-- adapter always asks the lane to force it; a backend that cannot
-- ignores the request and relies on the PCS alternating disparity on
-- its own.

entity sgmii_adapter is
  port(
    sgmii_i : in  sgmii_m2p_vector;
    sgmii_o : out sgmii_p2m_vector;

    tx_m_o : out nsl_transceiver.lane.tx_master_vector;
    tx_s_i : in  nsl_transceiver.lane.tx_slave_vector;
    rx_m_i : in  nsl_transceiver.lane.rx_master_vector;
    rx_s_o : out nsl_transceiver.lane.rx_slave_vector
    );
end entity;

architecture beh of sgmii_adapter is

  constant lane_count_c : natural := sgmii_i'length;

begin

  lanes_gen : for i in 0 to lane_count_c-1 generate

    constant sgmii_i_idx_c : natural := sgmii_i'low + i;
    constant sgmii_o_idx_c : natural := sgmii_o'low + i;
    constant tx_m_idx_c : natural := tx_m_o'low + i;
    constant rx_m_idx_c : natural := rx_m_i'low + i;
    constant rx_s_idx_c : natural := rx_s_o'low + i;

  begin

    -- Cluster RX lane -> SGMII ----------------------------------------------------------
    sgmii_o(sgmii_o_idx_c).symbol.data <= rx_m_i(rx_m_idx_c).data(0);
    sgmii_o(sgmii_o_idx_c).symbol.control <= rx_m_i(rx_m_idx_c).aux(0)(0);
    sgmii_o(sgmii_o_idx_c).code_err <= rx_m_i(rx_m_idx_c).aux(0)(1);
    sgmii_o(sgmii_o_idx_c).disparity_err <= rx_m_i(rx_m_idx_c).aux(0)(2);
    sgmii_o(sgmii_o_idx_c).align_ready <= rx_m_i(rx_m_idx_c).pcs_aligned;
    sgmii_o(sgmii_o_idx_c).clk_cor <= rx_m_i(rx_m_idx_c).clock_corrected;

    -- SGMII -> cluster TX lane ----------------------------------------------------------
    tx_m_o(tx_m_idx_c).data <= (
      0 => sgmii_i(sgmii_i_idx_c).symbol.data,
      others => (others => '-')
      );

    tx_m_o(tx_m_idx_c).aux <= (
      0 => (0 => sgmii_i(sgmii_i_idx_c).symbol.control,
            1 => '1',
            2 => sgmii_i(sgmii_i_idx_c).tx_disparity,
            others => '0'),
      others => (others => '-')
      );

    -- The PCS drives a symbol every cycle, so the lane always has
    -- one to send. sgmii_m2p_t.valid_symbol is not that bit: it
    -- scores the symbols coming back, and the serdes backend uses it
    -- to tell its alignment loop whether the delay it settled on is
    -- working. Gating transmission with it replaces the outgoing
    -- frame with the lane's idle pattern whenever the receive side
    -- momentarily dislikes what it got.
    tx_m_o(tx_m_idx_c).valid <= '1';
    tx_m_o(tx_m_idx_c).control <= (others => '0');
    tx_m_o(tx_m_idx_c).control_h <= (others => '0');
    tx_m_o(tx_m_idx_c).pcs_reset_n <= '1';
    tx_m_o(tx_m_idx_c).c2i_clock <= '0';

    -- SGMII frames its own lane, so the pattern generator stays out
    -- of the way.
    tx_m_o(tx_m_idx_c).prbs_select <= nsl_transceiver.lane.PRBS_NONE;
    tx_m_o(tx_m_idx_c).prbs_force_error <= '0';

    -- RX handshake: always accept -------------------------------------------------------
    rx_s_o(rx_s_idx_c).ready <= '1';
    rx_s_o(rx_s_idx_c).pcs_reset_n <= '1';
    rx_s_o(rx_s_idx_c).align_trigger <= sgmii_i(sgmii_i_idx_c).align_rst;
    rx_s_o(rx_s_idx_c).chbond_start <= '0';
    rx_s_o(rx_s_idx_c).control <= (others => '0');
    rx_s_o(rx_s_idx_c).prbs_select <= nsl_transceiver.lane.PRBS_NONE;
    rx_s_o(rx_s_idx_c).prbs_error_reset <= '0';

  end generate;

end architecture;
