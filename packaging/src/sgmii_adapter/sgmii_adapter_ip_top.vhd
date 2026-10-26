library ieee;
use ieee.std_logic_1164.all;

library nsl_mii, nsl_transceiver;
use nsl_mii.sgmii.all;
use nsl_transceiver.lane.all;

-- Vivado IP wrapper for nsl_transceiver.sgmii.sgmii_adapter, one lane.
--
-- Sits between sgmii_driver_ip_top and transceiver_cluster_series7_ip_top,
-- where sgmii_serdes_backend_series7_ip_top used to be:
--
--   sgmii_driver --sgmii--> sgmii_adapter --lane--> transceiver_cluster
--
-- IP-XACT cannot express record ports, so both sides are flattened:
--  - "sgmii" (nsl:interface:sgmii_symbol:1.0, slave side), same names as
--    the old serdes backend, so the driver connects the same way;
--  - "lane" (nsl:interface:transceiver_lane:1.0, master side), one lane of
--    the tx/rx master/slave records, byte 0 only (data_byte_count = 1).
--
-- The adapter is pure wiring and has no generic: lane count is one per
-- instance, line rate and polarity live in the cluster. It runs in the
-- cluster lane clock domain, the same clock the driver must use.

entity sgmii_adapter_ip_top is
  port(
    -- 8B/10B symbol interface from the driver (sgmii_m2p, driver -> adapter)
    m2p_data_i         : in std_logic_vector(7 downto 0);
    m2p_control_i      : in std_logic;
    m2p_tx_disparity_i : in std_logic := '0';
    m2p_align_rst_i    : in std_logic;
    m2p_valid_symbol_i : in std_logic;

    -- 8B/10B symbol interface to the driver (sgmii_p2m, adapter -> driver)
    p2m_data_o          : out std_logic_vector(7 downto 0);
    p2m_control_o       : out std_logic;
    p2m_code_err_o      : out std_logic;
    p2m_disparity_err_o : out std_logic;
    p2m_align_ready_o   : out std_logic;
    p2m_clk_cor_o       : out std_logic;

    -- Observation copies of p2m align_ready/code_err/disparity_err, outside
    -- the bus interface so an ILA/gatecap can tap them. Same clock domain
    -- as the bus. Leave unconnected when nothing watches them.
    align_ready_o   : out std_logic;
    code_err_o      : out std_logic;
    disparity_err_o : out std_logic;

    -- Lane, TX master (adapter -> cluster)
    lane_tx_data_o        : out std_logic_vector(7 downto 0);
    lane_tx_aux_o         : out std_logic_vector(7 downto 0);
    lane_tx_valid_o       : out std_logic;
    lane_tx_pcs_reset_n_o : out std_logic;
    lane_tx_control_o     : out std_logic_vector(63 downto 0);
    lane_tx_control_h_o   : out std_logic_vector(63 downto 0);
    lane_tx_c2i_clock_o   : out std_logic;
    -- Lane, TX slave (cluster -> adapter)
    lane_tx_ready_i       : in std_logic;
    lane_tx_pll_lock_i    : in std_logic;
    lane_tx_status_i      : in std_logic_vector(31 downto 0);
    -- Lane, RX master (cluster -> adapter)
    lane_rx_data_i        : in std_logic_vector(7 downto 0);
    lane_rx_aux_i         : in std_logic_vector(7 downto 0);
    lane_rx_valid_i       : in std_logic;
    lane_rx_pma_lock_i    : in std_logic;
    lane_rx_pcs_aligned_i : in std_logic;
    lane_rx_elec_idle_i   : in std_logic;
    lane_rx_status_i      : in std_logic_vector(31 downto 0);
    -- Lane, RX slave (adapter -> cluster)
    lane_rx_ready_o         : out std_logic;
    lane_rx_pcs_reset_n_o   : out std_logic;
    lane_rx_align_trigger_o : out std_logic;
    lane_rx_chbond_start_o  : out std_logic;
    lane_rx_control_o       : out std_logic_vector(63 downto 0)
    );
end entity;

architecture beh of sgmii_adapter_ip_top is

  attribute X_INTERFACE_INFO : string;

  -- sgmii_symbol bus, slave side. Instance name "sgmii" matches
  -- sgmii_driver_ip_top's master side.
  attribute X_INTERFACE_INFO of m2p_data_i : signal is "nsl:interface:sgmii_symbol:1.0 sgmii m2p_data";
  attribute X_INTERFACE_INFO of m2p_control_i : signal is "nsl:interface:sgmii_symbol:1.0 sgmii m2p_control";
  attribute X_INTERFACE_INFO of m2p_tx_disparity_i : signal is "nsl:interface:sgmii_symbol:1.0 sgmii m2p_tx_disparity";
  attribute X_INTERFACE_INFO of m2p_align_rst_i : signal is "nsl:interface:sgmii_symbol:1.0 sgmii m2p_align_rst";
  attribute X_INTERFACE_INFO of m2p_valid_symbol_i : signal is "nsl:interface:sgmii_symbol:1.0 sgmii m2p_valid_symbol";

  attribute X_INTERFACE_INFO of p2m_data_o : signal is "nsl:interface:sgmii_symbol:1.0 sgmii p2m_data";
  attribute X_INTERFACE_INFO of p2m_control_o : signal is "nsl:interface:sgmii_symbol:1.0 sgmii p2m_control";
  attribute X_INTERFACE_INFO of p2m_code_err_o : signal is "nsl:interface:sgmii_symbol:1.0 sgmii p2m_code_err";
  attribute X_INTERFACE_INFO of p2m_disparity_err_o : signal is "nsl:interface:sgmii_symbol:1.0 sgmii p2m_disparity_err";
  attribute X_INTERFACE_INFO of p2m_align_ready_o : signal is "nsl:interface:sgmii_symbol:1.0 sgmii p2m_align_ready";
  attribute X_INTERFACE_INFO of p2m_clk_cor_o : signal is "nsl:interface:sgmii_symbol:1.0 sgmii p2m_clk_cor";

  -- transceiver_lane bus, master side, to one laneN of the cluster.
  attribute X_INTERFACE_INFO of lane_tx_data_o : signal is "nsl:interface:transceiver_lane:1.0 lane tx_data";
  attribute X_INTERFACE_INFO of lane_tx_aux_o : signal is "nsl:interface:transceiver_lane:1.0 lane tx_aux";
  attribute X_INTERFACE_INFO of lane_tx_valid_o : signal is "nsl:interface:transceiver_lane:1.0 lane tx_valid";
  attribute X_INTERFACE_INFO of lane_tx_pcs_reset_n_o : signal is "nsl:interface:transceiver_lane:1.0 lane tx_pcs_reset_n";
  attribute X_INTERFACE_INFO of lane_tx_control_o : signal is "nsl:interface:transceiver_lane:1.0 lane tx_control";
  attribute X_INTERFACE_INFO of lane_tx_control_h_o : signal is "nsl:interface:transceiver_lane:1.0 lane tx_control_h";
  attribute X_INTERFACE_INFO of lane_tx_c2i_clock_o : signal is "nsl:interface:transceiver_lane:1.0 lane tx_c2i_clock";
  attribute X_INTERFACE_INFO of lane_tx_ready_i : signal is "nsl:interface:transceiver_lane:1.0 lane tx_ready";
  attribute X_INTERFACE_INFO of lane_tx_pll_lock_i : signal is "nsl:interface:transceiver_lane:1.0 lane tx_pll_lock";
  attribute X_INTERFACE_INFO of lane_tx_status_i : signal is "nsl:interface:transceiver_lane:1.0 lane tx_status";
  attribute X_INTERFACE_INFO of lane_rx_data_i : signal is "nsl:interface:transceiver_lane:1.0 lane rx_data";
  attribute X_INTERFACE_INFO of lane_rx_aux_i : signal is "nsl:interface:transceiver_lane:1.0 lane rx_aux";
  attribute X_INTERFACE_INFO of lane_rx_valid_i : signal is "nsl:interface:transceiver_lane:1.0 lane rx_valid";
  attribute X_INTERFACE_INFO of lane_rx_pma_lock_i : signal is "nsl:interface:transceiver_lane:1.0 lane rx_pma_lock";
  attribute X_INTERFACE_INFO of lane_rx_pcs_aligned_i : signal is "nsl:interface:transceiver_lane:1.0 lane rx_pcs_aligned";
  attribute X_INTERFACE_INFO of lane_rx_elec_idle_i : signal is "nsl:interface:transceiver_lane:1.0 lane rx_elec_idle";
  attribute X_INTERFACE_INFO of lane_rx_status_i : signal is "nsl:interface:transceiver_lane:1.0 lane rx_status";
  attribute X_INTERFACE_INFO of lane_rx_ready_o : signal is "nsl:interface:transceiver_lane:1.0 lane rx_ready";
  attribute X_INTERFACE_INFO of lane_rx_pcs_reset_n_o : signal is "nsl:interface:transceiver_lane:1.0 lane rx_pcs_reset_n";
  attribute X_INTERFACE_INFO of lane_rx_align_trigger_o : signal is "nsl:interface:transceiver_lane:1.0 lane rx_align_trigger";
  attribute X_INTERFACE_INFO of lane_rx_chbond_start_o : signal is "nsl:interface:transceiver_lane:1.0 lane rx_chbond_start";
  attribute X_INTERFACE_INFO of lane_rx_control_o : signal is "nsl:interface:transceiver_lane:1.0 lane rx_control";

  signal sgmii_m2p_s : sgmii_m2p_vector(0 to 0);
  signal sgmii_p2m_s : sgmii_p2m_vector(0 to 0);

  signal tx_m_s : tx_master_vector(0 to 0);
  signal tx_s_s : tx_slave_vector(0 to 0);
  signal rx_m_s : rx_master_vector(0 to 0);
  signal rx_s_s : rx_slave_vector(0 to 0);

begin

  -- m2p (driver -> adapter), flattened into the record the adapter reads.
  sgmii_m2p_s(0).data_m2p_symbol.data    <= std_ulogic_vector(m2p_data_i);
  sgmii_m2p_s(0).data_m2p_symbol.control <= m2p_control_i;
  sgmii_m2p_s(0).tx_disparity            <= m2p_tx_disparity_i;
  sgmii_m2p_s(0).align_rst               <= m2p_align_rst_i;
  sgmii_m2p_s(0).valid_symbol            <= m2p_valid_symbol_i;

  -- p2m (adapter -> driver), flattened out of the record the adapter drives.
  p2m_data_o          <= std_logic_vector(sgmii_p2m_s(0).data_p2m_symbol.data);
  p2m_control_o       <= sgmii_p2m_s(0).data_p2m_symbol.control;
  p2m_code_err_o      <= sgmii_p2m_s(0).code_err;
  p2m_disparity_err_o <= sgmii_p2m_s(0).disparity_err;
  p2m_align_ready_o   <= sgmii_p2m_s(0).align_ready;
  p2m_clk_cor_o       <= sgmii_p2m_s(0).clk_cor;

  align_ready_o   <= sgmii_p2m_s(0).align_ready;
  code_err_o      <= sgmii_p2m_s(0).code_err;
  disparity_err_o <= sgmii_p2m_s(0).disparity_err;

  -- Lane TX master, byte 0 only.
  lane_tx_data_o        <= std_logic_vector(tx_m_s(0).data(0));
  lane_tx_aux_o         <= std_logic_vector(tx_m_s(0).aux(0));
  lane_tx_valid_o       <= tx_m_s(0).valid;
  lane_tx_pcs_reset_n_o <= tx_m_s(0).pcs_reset_n;
  lane_tx_control_o     <= std_logic_vector(tx_m_s(0).control);
  lane_tx_control_h_o   <= std_logic_vector(tx_m_s(0).control_h);
  lane_tx_c2i_clock_o   <= tx_m_s(0).c2i_clock;

  tx_s_s(0).ready    <= lane_tx_ready_i;
  tx_s_s(0).pll_lock <= lane_tx_pll_lock_i;
  tx_s_s(0).status   <= std_ulogic_vector(lane_tx_status_i);

  -- Lane RX master, byte 0 only.
  rx_m_s(0).data        <= (0 => std_ulogic_vector(lane_rx_data_i), others => (others => '-'));
  rx_m_s(0).aux         <= (0 => std_ulogic_vector(lane_rx_aux_i), others => (others => '-'));
  rx_m_s(0).valid       <= lane_rx_valid_i;
  rx_m_s(0).pma_lock    <= lane_rx_pma_lock_i;
  rx_m_s(0).pcs_aligned <= lane_rx_pcs_aligned_i;
  rx_m_s(0).elec_idle   <= lane_rx_elec_idle_i;
  rx_m_s(0).status      <= std_ulogic_vector(lane_rx_status_i);

  lane_rx_ready_o         <= rx_s_s(0).ready;
  lane_rx_pcs_reset_n_o   <= rx_s_s(0).pcs_reset_n;
  lane_rx_align_trigger_o <= rx_s_s(0).align_trigger;
  lane_rx_chbond_start_o  <= rx_s_s(0).chbond_start;
  lane_rx_control_o       <= std_logic_vector(rx_s_s(0).control);

  adapter: nsl_transceiver.sgmii.sgmii_adapter
    port map(
      sgmii_i => sgmii_m2p_s,
      sgmii_o => sgmii_p2m_s,

      tx_m_o => tx_m_s,
      tx_s_i => tx_s_s,
      rx_m_i => rx_m_s,
      rx_s_o => rx_s_s
      );

end architecture;
