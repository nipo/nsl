library ieee;
use ieee.std_logic_1164.all;

library nsl_transceiver, nsl_io, nsl_amba, nsl_clocking, nsl_math;
use nsl_transceiver.lane.all;
use nsl_math.int_ext.all;

-- Vivado IP wrapper for nsl_transceiver.cluster.transceiver_cluster, series
-- 7 bulk IO SERDES architecture (transceiver_cluster_series7_serdes.vhd).
-- Replaces sgmii_serdes_backend_series7_ip_top. Pair each lane with an
-- sgmii_adapter_ip_top, then an sgmii_driver_ip_top:
--
--   sgmii_driver --sgmii--> sgmii_adapter --laneN--> transceiver_cluster
--
-- IP-XACT cannot express record ports nor a generic number of them, so the
-- wrapper exposes up to 4 lanes, each as:
--  - laneN    nsl:interface:transceiver_lane:1.0 slave, byte 0 of the
--             tx/rx master/slave records (data_byte_count = 1, which is all
--             this architecture supports);
--  - laneN_tx / laneN_rx  nsl:interface:diff_pair:1.0, the LVDS pads;
--  - laneN_clock_o  parallel word clock = line rate / 10 (125 MHz for
--             SGMII). All lanes share the same BUFR clock; the driver and
--             adapter of lane N must run on it;
--  - laneN_reset_n_o  lane ready (MMCM locked and IDELAYCTRL ready),
--             resynchronized on laneN_clock_o. Use it as the driver reset;
--  - laneN_pma_reset_n_i  kept for the cluster contract, unused by the
--             series 7 architecture.
-- Lanes at or above lane_count_c are disabled in the IP customization.
--
-- Configuration, mapped onto nsl_transceiver.cluster.config_t:
--  - lane_count_c       number of lanes, 1 to 4;
--  - refclk_mhz_c       ref_clock_i frequency in MHz, integer (the MMCM
--                       derives the 200 MHz IDELAYCTRL clock and the
--                       line rate / 2 serial clock from it);
--  - line_rate_mbps_c   line rate, 1250 for SGMII/1000BASE-X, common to all
--                       lanes (one MMCM for the cluster);
--  - laneN_loopback_c   NONE, NEAR_END_PCS, NEAR_END_PMA, FAR_END_PMA or
--                       FAR_END_PCS, see transceiver_cluster_series7_serdes;
--  - laneN_polarity_invert_tx_c / _rx_c  set when the board swaps P/N of
--                       that pair.
-- Fixed by this architecture: 8B/10B encoding, one byte per word, one PLL,
-- one refclk ("refclk0"), one user clock group. There is no runtime
-- configuration: the APB port is tied off.
--
-- All lanes sit on one BUFIO/BUFR pair, so all lane pins must be in the
-- same clock region, and the cluster owns an IDELAYCTRL: do not put two
-- instances (or this and an old sgmii_serdes_backend_series7) in the same
-- clock region.

entity transceiver_cluster_series7_ip_top is
  generic(
    lane_count_c     : integer := 1;
    refclk_mhz_c     : integer := 25;
    line_rate_mbps_c : integer := 1250;
    lane0_loopback_c           : string  := "NONE";
    lane0_polarity_invert_tx_c : boolean := false;
    lane0_polarity_invert_rx_c : boolean := false;
    lane1_loopback_c           : string  := "NONE";
    lane1_polarity_invert_tx_c : boolean := false;
    lane1_polarity_invert_rx_c : boolean := false;
    lane2_loopback_c           : string  := "NONE";
    lane2_polarity_invert_tx_c : boolean := false;
    lane2_polarity_invert_rx_c : boolean := false;
    lane3_loopback_c           : string  := "NONE";
    lane3_polarity_invert_tx_c : boolean := false;
    lane3_polarity_invert_rx_c : boolean := false
    );
  port(
    reset_n_i   : in std_logic;
    ref_clock_i : in std_logic;

    -- Lane 0
    lane0_txp : out std_logic;
    lane0_txn : out std_logic;
    lane0_rxp : in  std_logic;
    lane0_rxn : in  std_logic;

    lane0_clock_o       : out std_logic;
    lane0_reset_n_o     : out std_logic;
    lane0_pma_reset_n_i : in  std_logic := '1';

    lane0_tx_data_i : in std_logic_vector(7 downto 0) := (others => '0');
    lane0_tx_aux_i : in std_logic_vector(7 downto 0) := (others => '0');
    lane0_tx_valid_i : in std_logic := '0';
    lane0_tx_pcs_reset_n_i : in std_logic := '1';
    lane0_tx_control_i : in std_logic_vector(63 downto 0) := (others => '0');
    lane0_tx_control_h_i : in std_logic_vector(63 downto 0) := (others => '0');
    lane0_tx_c2i_clock_i : in std_logic := '0';
    lane0_tx_ready_o : out std_logic;
    lane0_tx_pll_lock_o : out std_logic;
    lane0_tx_status_o : out std_logic_vector(31 downto 0);
    lane0_rx_data_o : out std_logic_vector(7 downto 0);
    lane0_rx_aux_o : out std_logic_vector(7 downto 0);
    lane0_rx_valid_o : out std_logic;
    lane0_rx_pma_lock_o : out std_logic;
    lane0_rx_pcs_aligned_o : out std_logic;
    lane0_rx_elec_idle_o : out std_logic;
    lane0_rx_status_o : out std_logic_vector(31 downto 0);
    lane0_rx_ready_i : in std_logic := '1';
    lane0_rx_pcs_reset_n_i : in std_logic := '1';
    lane0_rx_align_trigger_i : in std_logic := '0';
    lane0_rx_chbond_start_i : in std_logic := '0';
    lane0_rx_control_i : in std_logic_vector(63 downto 0) := (others => '0');

    -- Lane 1
    lane1_txp : out std_logic;
    lane1_txn : out std_logic;
    lane1_rxp : in  std_logic;
    lane1_rxn : in  std_logic;

    lane1_clock_o       : out std_logic;
    lane1_reset_n_o     : out std_logic;
    lane1_pma_reset_n_i : in  std_logic := '1';

    lane1_tx_data_i : in std_logic_vector(7 downto 0) := (others => '0');
    lane1_tx_aux_i : in std_logic_vector(7 downto 0) := (others => '0');
    lane1_tx_valid_i : in std_logic := '0';
    lane1_tx_pcs_reset_n_i : in std_logic := '1';
    lane1_tx_control_i : in std_logic_vector(63 downto 0) := (others => '0');
    lane1_tx_control_h_i : in std_logic_vector(63 downto 0) := (others => '0');
    lane1_tx_c2i_clock_i : in std_logic := '0';
    lane1_tx_ready_o : out std_logic;
    lane1_tx_pll_lock_o : out std_logic;
    lane1_tx_status_o : out std_logic_vector(31 downto 0);
    lane1_rx_data_o : out std_logic_vector(7 downto 0);
    lane1_rx_aux_o : out std_logic_vector(7 downto 0);
    lane1_rx_valid_o : out std_logic;
    lane1_rx_pma_lock_o : out std_logic;
    lane1_rx_pcs_aligned_o : out std_logic;
    lane1_rx_elec_idle_o : out std_logic;
    lane1_rx_status_o : out std_logic_vector(31 downto 0);
    lane1_rx_ready_i : in std_logic := '1';
    lane1_rx_pcs_reset_n_i : in std_logic := '1';
    lane1_rx_align_trigger_i : in std_logic := '0';
    lane1_rx_chbond_start_i : in std_logic := '0';
    lane1_rx_control_i : in std_logic_vector(63 downto 0) := (others => '0');

    -- Lane 2
    lane2_txp : out std_logic;
    lane2_txn : out std_logic;
    lane2_rxp : in  std_logic;
    lane2_rxn : in  std_logic;

    lane2_clock_o       : out std_logic;
    lane2_reset_n_o     : out std_logic;
    lane2_pma_reset_n_i : in  std_logic := '1';

    lane2_tx_data_i : in std_logic_vector(7 downto 0) := (others => '0');
    lane2_tx_aux_i : in std_logic_vector(7 downto 0) := (others => '0');
    lane2_tx_valid_i : in std_logic := '0';
    lane2_tx_pcs_reset_n_i : in std_logic := '1';
    lane2_tx_control_i : in std_logic_vector(63 downto 0) := (others => '0');
    lane2_tx_control_h_i : in std_logic_vector(63 downto 0) := (others => '0');
    lane2_tx_c2i_clock_i : in std_logic := '0';
    lane2_tx_ready_o : out std_logic;
    lane2_tx_pll_lock_o : out std_logic;
    lane2_tx_status_o : out std_logic_vector(31 downto 0);
    lane2_rx_data_o : out std_logic_vector(7 downto 0);
    lane2_rx_aux_o : out std_logic_vector(7 downto 0);
    lane2_rx_valid_o : out std_logic;
    lane2_rx_pma_lock_o : out std_logic;
    lane2_rx_pcs_aligned_o : out std_logic;
    lane2_rx_elec_idle_o : out std_logic;
    lane2_rx_status_o : out std_logic_vector(31 downto 0);
    lane2_rx_ready_i : in std_logic := '1';
    lane2_rx_pcs_reset_n_i : in std_logic := '1';
    lane2_rx_align_trigger_i : in std_logic := '0';
    lane2_rx_chbond_start_i : in std_logic := '0';
    lane2_rx_control_i : in std_logic_vector(63 downto 0) := (others => '0');

    -- Lane 3
    lane3_txp : out std_logic;
    lane3_txn : out std_logic;
    lane3_rxp : in  std_logic;
    lane3_rxn : in  std_logic;

    lane3_clock_o       : out std_logic;
    lane3_reset_n_o     : out std_logic;
    lane3_pma_reset_n_i : in  std_logic := '1';

    lane3_tx_data_i : in std_logic_vector(7 downto 0) := (others => '0');
    lane3_tx_aux_i : in std_logic_vector(7 downto 0) := (others => '0');
    lane3_tx_valid_i : in std_logic := '0';
    lane3_tx_pcs_reset_n_i : in std_logic := '1';
    lane3_tx_control_i : in std_logic_vector(63 downto 0) := (others => '0');
    lane3_tx_control_h_i : in std_logic_vector(63 downto 0) := (others => '0');
    lane3_tx_c2i_clock_i : in std_logic := '0';
    lane3_tx_ready_o : out std_logic;
    lane3_tx_pll_lock_o : out std_logic;
    lane3_tx_status_o : out std_logic_vector(31 downto 0);
    lane3_rx_data_o : out std_logic_vector(7 downto 0);
    lane3_rx_aux_o : out std_logic_vector(7 downto 0);
    lane3_rx_valid_o : out std_logic;
    lane3_rx_pma_lock_o : out std_logic;
    lane3_rx_pcs_aligned_o : out std_logic;
    lane3_rx_elec_idle_o : out std_logic;
    lane3_rx_status_o : out std_logic_vector(31 downto 0);
    lane3_rx_ready_i : in std_logic := '1';
    lane3_rx_pcs_reset_n_i : in std_logic := '1';
    lane3_rx_align_trigger_i : in std_logic := '0';
    lane3_rx_chbond_start_i : in std_logic := '0';
    lane3_rx_control_i : in std_logic_vector(63 downto 0) := (others => '0')
    );
end entity;

architecture beh of transceiver_cluster_series7_ip_top is

  attribute X_INTERFACE_INFO : string;
  attribute X_INTERFACE_PARAMETER : string;

  attribute X_INTERFACE_INFO of ref_clock_i : signal is "xilinx.com:signal:clock:1.0 ref_clock_i CLK";
  attribute X_INTERFACE_INFO of reset_n_i : signal is "xilinx.com:signal:reset:1.0 reset_n_i RST";
  attribute X_INTERFACE_PARAMETER of reset_n_i : signal is "POLARITY ACTIVE_LOW";

  -- Lane 0. FREQ_HZ is the SGMII word clock (1250 Mb/s / 10). It is static
  -- in the packaged IP: if line_rate_mbps_c changes, it no longer matches.
  attribute X_INTERFACE_INFO of lane0_clock_o : signal is "xilinx.com:signal:clock:1.0 lane0_clock_o CLK";
  attribute X_INTERFACE_PARAMETER of lane0_clock_o : signal is "ASSOCIATED_BUSIF lane0, ASSOCIATED_RESET lane0_reset_n_o, FREQ_HZ 125000000";
  attribute X_INTERFACE_INFO of lane0_reset_n_o : signal is "xilinx.com:signal:reset:1.0 lane0_reset_n_o RST";
  attribute X_INTERFACE_PARAMETER of lane0_reset_n_o : signal is "POLARITY ACTIVE_LOW";
  attribute X_INTERFACE_INFO of lane0_pma_reset_n_i : signal is "xilinx.com:signal:reset:1.0 lane0_pma_reset_n_i RST";
  attribute X_INTERFACE_PARAMETER of lane0_pma_reset_n_i : signal is "POLARITY ACTIVE_LOW";

  attribute X_INTERFACE_INFO of lane0_txp : signal is "nsl:interface:diff_pair:1.0 lane0_tx p";
  attribute X_INTERFACE_INFO of lane0_txn : signal is "nsl:interface:diff_pair:1.0 lane0_tx n";
  attribute X_INTERFACE_INFO of lane0_rxp : signal is "nsl:interface:diff_pair:1.0 lane0_rx p";
  attribute X_INTERFACE_INFO of lane0_rxn : signal is "nsl:interface:diff_pair:1.0 lane0_rx n";

  attribute X_INTERFACE_INFO of lane0_tx_data_i : signal is "nsl:interface:transceiver_lane:1.0 lane0 tx_data";
  attribute X_INTERFACE_INFO of lane0_tx_aux_i : signal is "nsl:interface:transceiver_lane:1.0 lane0 tx_aux";
  attribute X_INTERFACE_INFO of lane0_tx_valid_i : signal is "nsl:interface:transceiver_lane:1.0 lane0 tx_valid";
  attribute X_INTERFACE_INFO of lane0_tx_pcs_reset_n_i : signal is "nsl:interface:transceiver_lane:1.0 lane0 tx_pcs_reset_n";
  attribute X_INTERFACE_INFO of lane0_tx_control_i : signal is "nsl:interface:transceiver_lane:1.0 lane0 tx_control";
  attribute X_INTERFACE_INFO of lane0_tx_control_h_i : signal is "nsl:interface:transceiver_lane:1.0 lane0 tx_control_h";
  attribute X_INTERFACE_INFO of lane0_tx_c2i_clock_i : signal is "nsl:interface:transceiver_lane:1.0 lane0 tx_c2i_clock";
  attribute X_INTERFACE_INFO of lane0_tx_ready_o : signal is "nsl:interface:transceiver_lane:1.0 lane0 tx_ready";
  attribute X_INTERFACE_INFO of lane0_tx_pll_lock_o : signal is "nsl:interface:transceiver_lane:1.0 lane0 tx_pll_lock";
  attribute X_INTERFACE_INFO of lane0_tx_status_o : signal is "nsl:interface:transceiver_lane:1.0 lane0 tx_status";
  attribute X_INTERFACE_INFO of lane0_rx_data_o : signal is "nsl:interface:transceiver_lane:1.0 lane0 rx_data";
  attribute X_INTERFACE_INFO of lane0_rx_aux_o : signal is "nsl:interface:transceiver_lane:1.0 lane0 rx_aux";
  attribute X_INTERFACE_INFO of lane0_rx_valid_o : signal is "nsl:interface:transceiver_lane:1.0 lane0 rx_valid";
  attribute X_INTERFACE_INFO of lane0_rx_pma_lock_o : signal is "nsl:interface:transceiver_lane:1.0 lane0 rx_pma_lock";
  attribute X_INTERFACE_INFO of lane0_rx_pcs_aligned_o : signal is "nsl:interface:transceiver_lane:1.0 lane0 rx_pcs_aligned";
  attribute X_INTERFACE_INFO of lane0_rx_elec_idle_o : signal is "nsl:interface:transceiver_lane:1.0 lane0 rx_elec_idle";
  attribute X_INTERFACE_INFO of lane0_rx_status_o : signal is "nsl:interface:transceiver_lane:1.0 lane0 rx_status";
  attribute X_INTERFACE_INFO of lane0_rx_ready_i : signal is "nsl:interface:transceiver_lane:1.0 lane0 rx_ready";
  attribute X_INTERFACE_INFO of lane0_rx_pcs_reset_n_i : signal is "nsl:interface:transceiver_lane:1.0 lane0 rx_pcs_reset_n";
  attribute X_INTERFACE_INFO of lane0_rx_align_trigger_i : signal is "nsl:interface:transceiver_lane:1.0 lane0 rx_align_trigger";
  attribute X_INTERFACE_INFO of lane0_rx_chbond_start_i : signal is "nsl:interface:transceiver_lane:1.0 lane0 rx_chbond_start";
  attribute X_INTERFACE_INFO of lane0_rx_control_i : signal is "nsl:interface:transceiver_lane:1.0 lane0 rx_control";

  -- Lane 1. FREQ_HZ is the SGMII word clock (1250 Mb/s / 10). It is static
  -- in the packaged IP: if line_rate_mbps_c changes, it no longer matches.
  attribute X_INTERFACE_INFO of lane1_clock_o : signal is "xilinx.com:signal:clock:1.0 lane1_clock_o CLK";
  attribute X_INTERFACE_PARAMETER of lane1_clock_o : signal is "ASSOCIATED_BUSIF lane1, ASSOCIATED_RESET lane1_reset_n_o, FREQ_HZ 125000000";
  attribute X_INTERFACE_INFO of lane1_reset_n_o : signal is "xilinx.com:signal:reset:1.0 lane1_reset_n_o RST";
  attribute X_INTERFACE_PARAMETER of lane1_reset_n_o : signal is "POLARITY ACTIVE_LOW";
  attribute X_INTERFACE_INFO of lane1_pma_reset_n_i : signal is "xilinx.com:signal:reset:1.0 lane1_pma_reset_n_i RST";
  attribute X_INTERFACE_PARAMETER of lane1_pma_reset_n_i : signal is "POLARITY ACTIVE_LOW";

  attribute X_INTERFACE_INFO of lane1_txp : signal is "nsl:interface:diff_pair:1.0 lane1_tx p";
  attribute X_INTERFACE_INFO of lane1_txn : signal is "nsl:interface:diff_pair:1.0 lane1_tx n";
  attribute X_INTERFACE_INFO of lane1_rxp : signal is "nsl:interface:diff_pair:1.0 lane1_rx p";
  attribute X_INTERFACE_INFO of lane1_rxn : signal is "nsl:interface:diff_pair:1.0 lane1_rx n";

  attribute X_INTERFACE_INFO of lane1_tx_data_i : signal is "nsl:interface:transceiver_lane:1.0 lane1 tx_data";
  attribute X_INTERFACE_INFO of lane1_tx_aux_i : signal is "nsl:interface:transceiver_lane:1.0 lane1 tx_aux";
  attribute X_INTERFACE_INFO of lane1_tx_valid_i : signal is "nsl:interface:transceiver_lane:1.0 lane1 tx_valid";
  attribute X_INTERFACE_INFO of lane1_tx_pcs_reset_n_i : signal is "nsl:interface:transceiver_lane:1.0 lane1 tx_pcs_reset_n";
  attribute X_INTERFACE_INFO of lane1_tx_control_i : signal is "nsl:interface:transceiver_lane:1.0 lane1 tx_control";
  attribute X_INTERFACE_INFO of lane1_tx_control_h_i : signal is "nsl:interface:transceiver_lane:1.0 lane1 tx_control_h";
  attribute X_INTERFACE_INFO of lane1_tx_c2i_clock_i : signal is "nsl:interface:transceiver_lane:1.0 lane1 tx_c2i_clock";
  attribute X_INTERFACE_INFO of lane1_tx_ready_o : signal is "nsl:interface:transceiver_lane:1.0 lane1 tx_ready";
  attribute X_INTERFACE_INFO of lane1_tx_pll_lock_o : signal is "nsl:interface:transceiver_lane:1.0 lane1 tx_pll_lock";
  attribute X_INTERFACE_INFO of lane1_tx_status_o : signal is "nsl:interface:transceiver_lane:1.0 lane1 tx_status";
  attribute X_INTERFACE_INFO of lane1_rx_data_o : signal is "nsl:interface:transceiver_lane:1.0 lane1 rx_data";
  attribute X_INTERFACE_INFO of lane1_rx_aux_o : signal is "nsl:interface:transceiver_lane:1.0 lane1 rx_aux";
  attribute X_INTERFACE_INFO of lane1_rx_valid_o : signal is "nsl:interface:transceiver_lane:1.0 lane1 rx_valid";
  attribute X_INTERFACE_INFO of lane1_rx_pma_lock_o : signal is "nsl:interface:transceiver_lane:1.0 lane1 rx_pma_lock";
  attribute X_INTERFACE_INFO of lane1_rx_pcs_aligned_o : signal is "nsl:interface:transceiver_lane:1.0 lane1 rx_pcs_aligned";
  attribute X_INTERFACE_INFO of lane1_rx_elec_idle_o : signal is "nsl:interface:transceiver_lane:1.0 lane1 rx_elec_idle";
  attribute X_INTERFACE_INFO of lane1_rx_status_o : signal is "nsl:interface:transceiver_lane:1.0 lane1 rx_status";
  attribute X_INTERFACE_INFO of lane1_rx_ready_i : signal is "nsl:interface:transceiver_lane:1.0 lane1 rx_ready";
  attribute X_INTERFACE_INFO of lane1_rx_pcs_reset_n_i : signal is "nsl:interface:transceiver_lane:1.0 lane1 rx_pcs_reset_n";
  attribute X_INTERFACE_INFO of lane1_rx_align_trigger_i : signal is "nsl:interface:transceiver_lane:1.0 lane1 rx_align_trigger";
  attribute X_INTERFACE_INFO of lane1_rx_chbond_start_i : signal is "nsl:interface:transceiver_lane:1.0 lane1 rx_chbond_start";
  attribute X_INTERFACE_INFO of lane1_rx_control_i : signal is "nsl:interface:transceiver_lane:1.0 lane1 rx_control";

  -- Lane 2. FREQ_HZ is the SGMII word clock (1250 Mb/s / 10). It is static
  -- in the packaged IP: if line_rate_mbps_c changes, it no longer matches.
  attribute X_INTERFACE_INFO of lane2_clock_o : signal is "xilinx.com:signal:clock:1.0 lane2_clock_o CLK";
  attribute X_INTERFACE_PARAMETER of lane2_clock_o : signal is "ASSOCIATED_BUSIF lane2, ASSOCIATED_RESET lane2_reset_n_o, FREQ_HZ 125000000";
  attribute X_INTERFACE_INFO of lane2_reset_n_o : signal is "xilinx.com:signal:reset:1.0 lane2_reset_n_o RST";
  attribute X_INTERFACE_PARAMETER of lane2_reset_n_o : signal is "POLARITY ACTIVE_LOW";
  attribute X_INTERFACE_INFO of lane2_pma_reset_n_i : signal is "xilinx.com:signal:reset:1.0 lane2_pma_reset_n_i RST";
  attribute X_INTERFACE_PARAMETER of lane2_pma_reset_n_i : signal is "POLARITY ACTIVE_LOW";

  attribute X_INTERFACE_INFO of lane2_txp : signal is "nsl:interface:diff_pair:1.0 lane2_tx p";
  attribute X_INTERFACE_INFO of lane2_txn : signal is "nsl:interface:diff_pair:1.0 lane2_tx n";
  attribute X_INTERFACE_INFO of lane2_rxp : signal is "nsl:interface:diff_pair:1.0 lane2_rx p";
  attribute X_INTERFACE_INFO of lane2_rxn : signal is "nsl:interface:diff_pair:1.0 lane2_rx n";

  attribute X_INTERFACE_INFO of lane2_tx_data_i : signal is "nsl:interface:transceiver_lane:1.0 lane2 tx_data";
  attribute X_INTERFACE_INFO of lane2_tx_aux_i : signal is "nsl:interface:transceiver_lane:1.0 lane2 tx_aux";
  attribute X_INTERFACE_INFO of lane2_tx_valid_i : signal is "nsl:interface:transceiver_lane:1.0 lane2 tx_valid";
  attribute X_INTERFACE_INFO of lane2_tx_pcs_reset_n_i : signal is "nsl:interface:transceiver_lane:1.0 lane2 tx_pcs_reset_n";
  attribute X_INTERFACE_INFO of lane2_tx_control_i : signal is "nsl:interface:transceiver_lane:1.0 lane2 tx_control";
  attribute X_INTERFACE_INFO of lane2_tx_control_h_i : signal is "nsl:interface:transceiver_lane:1.0 lane2 tx_control_h";
  attribute X_INTERFACE_INFO of lane2_tx_c2i_clock_i : signal is "nsl:interface:transceiver_lane:1.0 lane2 tx_c2i_clock";
  attribute X_INTERFACE_INFO of lane2_tx_ready_o : signal is "nsl:interface:transceiver_lane:1.0 lane2 tx_ready";
  attribute X_INTERFACE_INFO of lane2_tx_pll_lock_o : signal is "nsl:interface:transceiver_lane:1.0 lane2 tx_pll_lock";
  attribute X_INTERFACE_INFO of lane2_tx_status_o : signal is "nsl:interface:transceiver_lane:1.0 lane2 tx_status";
  attribute X_INTERFACE_INFO of lane2_rx_data_o : signal is "nsl:interface:transceiver_lane:1.0 lane2 rx_data";
  attribute X_INTERFACE_INFO of lane2_rx_aux_o : signal is "nsl:interface:transceiver_lane:1.0 lane2 rx_aux";
  attribute X_INTERFACE_INFO of lane2_rx_valid_o : signal is "nsl:interface:transceiver_lane:1.0 lane2 rx_valid";
  attribute X_INTERFACE_INFO of lane2_rx_pma_lock_o : signal is "nsl:interface:transceiver_lane:1.0 lane2 rx_pma_lock";
  attribute X_INTERFACE_INFO of lane2_rx_pcs_aligned_o : signal is "nsl:interface:transceiver_lane:1.0 lane2 rx_pcs_aligned";
  attribute X_INTERFACE_INFO of lane2_rx_elec_idle_o : signal is "nsl:interface:transceiver_lane:1.0 lane2 rx_elec_idle";
  attribute X_INTERFACE_INFO of lane2_rx_status_o : signal is "nsl:interface:transceiver_lane:1.0 lane2 rx_status";
  attribute X_INTERFACE_INFO of lane2_rx_ready_i : signal is "nsl:interface:transceiver_lane:1.0 lane2 rx_ready";
  attribute X_INTERFACE_INFO of lane2_rx_pcs_reset_n_i : signal is "nsl:interface:transceiver_lane:1.0 lane2 rx_pcs_reset_n";
  attribute X_INTERFACE_INFO of lane2_rx_align_trigger_i : signal is "nsl:interface:transceiver_lane:1.0 lane2 rx_align_trigger";
  attribute X_INTERFACE_INFO of lane2_rx_chbond_start_i : signal is "nsl:interface:transceiver_lane:1.0 lane2 rx_chbond_start";
  attribute X_INTERFACE_INFO of lane2_rx_control_i : signal is "nsl:interface:transceiver_lane:1.0 lane2 rx_control";

  -- Lane 3. FREQ_HZ is the SGMII word clock (1250 Mb/s / 10). It is static
  -- in the packaged IP: if line_rate_mbps_c changes, it no longer matches.
  attribute X_INTERFACE_INFO of lane3_clock_o : signal is "xilinx.com:signal:clock:1.0 lane3_clock_o CLK";
  attribute X_INTERFACE_PARAMETER of lane3_clock_o : signal is "ASSOCIATED_BUSIF lane3, ASSOCIATED_RESET lane3_reset_n_o, FREQ_HZ 125000000";
  attribute X_INTERFACE_INFO of lane3_reset_n_o : signal is "xilinx.com:signal:reset:1.0 lane3_reset_n_o RST";
  attribute X_INTERFACE_PARAMETER of lane3_reset_n_o : signal is "POLARITY ACTIVE_LOW";
  attribute X_INTERFACE_INFO of lane3_pma_reset_n_i : signal is "xilinx.com:signal:reset:1.0 lane3_pma_reset_n_i RST";
  attribute X_INTERFACE_PARAMETER of lane3_pma_reset_n_i : signal is "POLARITY ACTIVE_LOW";

  attribute X_INTERFACE_INFO of lane3_txp : signal is "nsl:interface:diff_pair:1.0 lane3_tx p";
  attribute X_INTERFACE_INFO of lane3_txn : signal is "nsl:interface:diff_pair:1.0 lane3_tx n";
  attribute X_INTERFACE_INFO of lane3_rxp : signal is "nsl:interface:diff_pair:1.0 lane3_rx p";
  attribute X_INTERFACE_INFO of lane3_rxn : signal is "nsl:interface:diff_pair:1.0 lane3_rx n";

  attribute X_INTERFACE_INFO of lane3_tx_data_i : signal is "nsl:interface:transceiver_lane:1.0 lane3 tx_data";
  attribute X_INTERFACE_INFO of lane3_tx_aux_i : signal is "nsl:interface:transceiver_lane:1.0 lane3 tx_aux";
  attribute X_INTERFACE_INFO of lane3_tx_valid_i : signal is "nsl:interface:transceiver_lane:1.0 lane3 tx_valid";
  attribute X_INTERFACE_INFO of lane3_tx_pcs_reset_n_i : signal is "nsl:interface:transceiver_lane:1.0 lane3 tx_pcs_reset_n";
  attribute X_INTERFACE_INFO of lane3_tx_control_i : signal is "nsl:interface:transceiver_lane:1.0 lane3 tx_control";
  attribute X_INTERFACE_INFO of lane3_tx_control_h_i : signal is "nsl:interface:transceiver_lane:1.0 lane3 tx_control_h";
  attribute X_INTERFACE_INFO of lane3_tx_c2i_clock_i : signal is "nsl:interface:transceiver_lane:1.0 lane3 tx_c2i_clock";
  attribute X_INTERFACE_INFO of lane3_tx_ready_o : signal is "nsl:interface:transceiver_lane:1.0 lane3 tx_ready";
  attribute X_INTERFACE_INFO of lane3_tx_pll_lock_o : signal is "nsl:interface:transceiver_lane:1.0 lane3 tx_pll_lock";
  attribute X_INTERFACE_INFO of lane3_tx_status_o : signal is "nsl:interface:transceiver_lane:1.0 lane3 tx_status";
  attribute X_INTERFACE_INFO of lane3_rx_data_o : signal is "nsl:interface:transceiver_lane:1.0 lane3 rx_data";
  attribute X_INTERFACE_INFO of lane3_rx_aux_o : signal is "nsl:interface:transceiver_lane:1.0 lane3 rx_aux";
  attribute X_INTERFACE_INFO of lane3_rx_valid_o : signal is "nsl:interface:transceiver_lane:1.0 lane3 rx_valid";
  attribute X_INTERFACE_INFO of lane3_rx_pma_lock_o : signal is "nsl:interface:transceiver_lane:1.0 lane3 rx_pma_lock";
  attribute X_INTERFACE_INFO of lane3_rx_pcs_aligned_o : signal is "nsl:interface:transceiver_lane:1.0 lane3 rx_pcs_aligned";
  attribute X_INTERFACE_INFO of lane3_rx_elec_idle_o : signal is "nsl:interface:transceiver_lane:1.0 lane3 rx_elec_idle";
  attribute X_INTERFACE_INFO of lane3_rx_status_o : signal is "nsl:interface:transceiver_lane:1.0 lane3 rx_status";
  attribute X_INTERFACE_INFO of lane3_rx_ready_i : signal is "nsl:interface:transceiver_lane:1.0 lane3 rx_ready";
  attribute X_INTERFACE_INFO of lane3_rx_pcs_reset_n_i : signal is "nsl:interface:transceiver_lane:1.0 lane3 rx_pcs_reset_n";
  attribute X_INTERFACE_INFO of lane3_rx_align_trigger_i : signal is "nsl:interface:transceiver_lane:1.0 lane3 rx_align_trigger";
  attribute X_INTERFACE_INFO of lane3_rx_chbond_start_i : signal is "nsl:interface:transceiver_lane:1.0 lane3 rx_chbond_start";
  attribute X_INTERFACE_INFO of lane3_rx_control_i : signal is "nsl:interface:transceiver_lane:1.0 lane3 rx_control";

  constant max_lane_count_c : natural := 4;

  type boolean_vector is array (natural range <>) of boolean;
  type loopback_vector is array (natural range <>) of loopback_mode_t;

  function to_loopback(name : string) return loopback_mode_t is
  begin
    if name = "NONE" then
      return LOOPBACK_NONE;
    elsif name = "NEAR_END_PCS" then
      return LOOPBACK_NEAR_END_PCS;
    elsif name = "NEAR_END_PMA" then
      return LOOPBACK_NEAR_END_PMA;
    elsif name = "FAR_END_PMA" then
      return LOOPBACK_FAR_END_PMA;
    elsif name = "FAR_END_PCS" then
      return LOOPBACK_FAR_END_PCS;
    end if;
    assert false
      report "transceiver_cluster_series7_ip_top: unknown loopback mode '" & name & "'"
      severity failure;
    return LOOPBACK_NONE;
  end function;

  constant loopback_c : loopback_vector(0 to max_lane_count_c-1) := (
    to_loopback(lane0_loopback_c),
    to_loopback(lane1_loopback_c),
    to_loopback(lane2_loopback_c),
    to_loopback(lane3_loopback_c)
    );
  constant polarity_invert_tx_c : boolean_vector(0 to max_lane_count_c-1) := (
    lane0_polarity_invert_tx_c,
    lane1_polarity_invert_tx_c,
    lane2_polarity_invert_tx_c,
    lane3_polarity_invert_tx_c
    );
  constant polarity_invert_rx_c : boolean_vector(0 to max_lane_count_c-1) := (
    lane0_polarity_invert_rx_c,
    lane1_polarity_invert_rx_c,
    lane2_polarity_invert_rx_c,
    lane3_polarity_invert_rx_c
    );

  function lanes_config return config_vector is
    variable ret : config_vector(0 to lane_count_c-1);
  begin
    for i in ret'range loop
      ret(i) := nsl_transceiver.lane.config(
        data_byte_count    => 1,
        encoding           => ENCODING_8B10B,
        line_rate_mbps     => line_rate_mbps_c,
        pll_index          => 0,
        ref_clock_index    => 0,
        user_clock_group_index => 0,
        polarity_invert_tx => polarity_invert_tx_c(i),
        polarity_invert_rx => polarity_invert_rx_c(i),
        loopback           => loopback_c(i));
    end loop;
    return ret;
  end function;

  constant cluster_config_c : nsl_transceiver.cluster.config_t := nsl_transceiver.cluster.config(
    plls => (0 => (enabled => true,
                   ref_clock_index => 0,
                   ref_clock_mhz => refclk_mhz_c,
                   target_vco_mhz => 0)),
    refclks => (0 => (ref_clock_index => 0,
                      ref_clock_mhz => refclk_mhz_c)),
    lanes => lanes_config,
    user_clock_group_count => 1);

  constant ref_clock_c : integer_vector(0 to 0) := (0 => nsl_transceiver.target.clock_id("refclk0"));

  -- Cluster side, lane_count_c wide.
  signal lane_tx_s, lane_rx_s : nsl_io.diff.diff_pair_vector(0 to lane_count_c-1);
  signal lane_clock_s, pma_reset_n_s : std_ulogic_vector(0 to lane_count_c-1);
  signal tx_m_s : tx_master_vector(0 to lane_count_c-1);
  signal tx_s_s : tx_slave_vector(0 to lane_count_c-1);
  signal rx_m_s : rx_master_vector(0 to lane_count_c-1);
  signal rx_s_s : rx_slave_vector(0 to lane_count_c-1);

  -- Port side, max_lane_count_c wide, lanes past lane_count_c tied off.
  signal lane_tx_all_s, lane_rx_all_s : nsl_io.diff.diff_pair_vector(0 to max_lane_count_c-1);
  signal lane_clock_all_s, lane_reset_n_all_s, pma_reset_n_all_s : std_ulogic_vector(0 to max_lane_count_c-1);
  signal tx_m_all_s : tx_master_vector(0 to max_lane_count_c-1);
  signal tx_s_all_s : tx_slave_vector(0 to max_lane_count_c-1);
  signal rx_m_all_s : rx_master_vector(0 to max_lane_count_c-1);
  signal rx_s_all_s : rx_slave_vector(0 to max_lane_count_c-1);

begin

  assert lane_count_c >= 1 and lane_count_c <= max_lane_count_c
    report "transceiver_cluster_series7_ip_top: lane_count_c must be 1 to 4"
    severity failure;

  -- Lane 0 ports
  lane_rx_all_s(0).p <= lane0_rxp;
  lane_rx_all_s(0).n <= lane0_rxn;
  lane0_txp <= lane_tx_all_s(0).p;
  lane0_txn <= lane_tx_all_s(0).n;
  lane0_clock_o <= lane_clock_all_s(0);
  lane0_reset_n_o <= lane_reset_n_all_s(0);
  pma_reset_n_all_s(0) <= lane0_pma_reset_n_i;

  tx_m_all_s(0).data <= (0 => std_ulogic_vector(lane0_tx_data_i), others => (others => '-'));
  tx_m_all_s(0).aux <= (0 => std_ulogic_vector(lane0_tx_aux_i), others => (others => '-'));
  tx_m_all_s(0).valid <= lane0_tx_valid_i;
  tx_m_all_s(0).pcs_reset_n <= lane0_tx_pcs_reset_n_i;
  tx_m_all_s(0).control <= std_ulogic_vector(lane0_tx_control_i);
  tx_m_all_s(0).control_h <= std_ulogic_vector(lane0_tx_control_h_i);
  tx_m_all_s(0).c2i_clock <= lane0_tx_c2i_clock_i;
  lane0_tx_ready_o <= tx_s_all_s(0).ready;
  lane0_tx_pll_lock_o <= tx_s_all_s(0).pll_lock;
  lane0_tx_status_o <= std_logic_vector(tx_s_all_s(0).status);
  lane0_rx_data_o <= std_logic_vector(rx_m_all_s(0).data(0));
  lane0_rx_aux_o <= std_logic_vector(rx_m_all_s(0).aux(0));
  lane0_rx_valid_o <= rx_m_all_s(0).valid;
  lane0_rx_pma_lock_o <= rx_m_all_s(0).pma_lock;
  lane0_rx_pcs_aligned_o <= rx_m_all_s(0).pcs_aligned;
  lane0_rx_elec_idle_o <= rx_m_all_s(0).elec_idle;
  lane0_rx_status_o <= std_logic_vector(rx_m_all_s(0).status);
  rx_s_all_s(0).ready <= lane0_rx_ready_i;
  rx_s_all_s(0).pcs_reset_n <= lane0_rx_pcs_reset_n_i;
  rx_s_all_s(0).align_trigger <= lane0_rx_align_trigger_i;
  rx_s_all_s(0).chbond_start <= lane0_rx_chbond_start_i;
  rx_s_all_s(0).control <= std_ulogic_vector(lane0_rx_control_i);

  -- Lane 1 ports
  lane_rx_all_s(1).p <= lane1_rxp;
  lane_rx_all_s(1).n <= lane1_rxn;
  lane1_txp <= lane_tx_all_s(1).p;
  lane1_txn <= lane_tx_all_s(1).n;
  lane1_clock_o <= lane_clock_all_s(1);
  lane1_reset_n_o <= lane_reset_n_all_s(1);
  pma_reset_n_all_s(1) <= lane1_pma_reset_n_i;

  tx_m_all_s(1).data <= (0 => std_ulogic_vector(lane1_tx_data_i), others => (others => '-'));
  tx_m_all_s(1).aux <= (0 => std_ulogic_vector(lane1_tx_aux_i), others => (others => '-'));
  tx_m_all_s(1).valid <= lane1_tx_valid_i;
  tx_m_all_s(1).pcs_reset_n <= lane1_tx_pcs_reset_n_i;
  tx_m_all_s(1).control <= std_ulogic_vector(lane1_tx_control_i);
  tx_m_all_s(1).control_h <= std_ulogic_vector(lane1_tx_control_h_i);
  tx_m_all_s(1).c2i_clock <= lane1_tx_c2i_clock_i;
  lane1_tx_ready_o <= tx_s_all_s(1).ready;
  lane1_tx_pll_lock_o <= tx_s_all_s(1).pll_lock;
  lane1_tx_status_o <= std_logic_vector(tx_s_all_s(1).status);
  lane1_rx_data_o <= std_logic_vector(rx_m_all_s(1).data(0));
  lane1_rx_aux_o <= std_logic_vector(rx_m_all_s(1).aux(0));
  lane1_rx_valid_o <= rx_m_all_s(1).valid;
  lane1_rx_pma_lock_o <= rx_m_all_s(1).pma_lock;
  lane1_rx_pcs_aligned_o <= rx_m_all_s(1).pcs_aligned;
  lane1_rx_elec_idle_o <= rx_m_all_s(1).elec_idle;
  lane1_rx_status_o <= std_logic_vector(rx_m_all_s(1).status);
  rx_s_all_s(1).ready <= lane1_rx_ready_i;
  rx_s_all_s(1).pcs_reset_n <= lane1_rx_pcs_reset_n_i;
  rx_s_all_s(1).align_trigger <= lane1_rx_align_trigger_i;
  rx_s_all_s(1).chbond_start <= lane1_rx_chbond_start_i;
  rx_s_all_s(1).control <= std_ulogic_vector(lane1_rx_control_i);

  -- Lane 2 ports
  lane_rx_all_s(2).p <= lane2_rxp;
  lane_rx_all_s(2).n <= lane2_rxn;
  lane2_txp <= lane_tx_all_s(2).p;
  lane2_txn <= lane_tx_all_s(2).n;
  lane2_clock_o <= lane_clock_all_s(2);
  lane2_reset_n_o <= lane_reset_n_all_s(2);
  pma_reset_n_all_s(2) <= lane2_pma_reset_n_i;

  tx_m_all_s(2).data <= (0 => std_ulogic_vector(lane2_tx_data_i), others => (others => '-'));
  tx_m_all_s(2).aux <= (0 => std_ulogic_vector(lane2_tx_aux_i), others => (others => '-'));
  tx_m_all_s(2).valid <= lane2_tx_valid_i;
  tx_m_all_s(2).pcs_reset_n <= lane2_tx_pcs_reset_n_i;
  tx_m_all_s(2).control <= std_ulogic_vector(lane2_tx_control_i);
  tx_m_all_s(2).control_h <= std_ulogic_vector(lane2_tx_control_h_i);
  tx_m_all_s(2).c2i_clock <= lane2_tx_c2i_clock_i;
  lane2_tx_ready_o <= tx_s_all_s(2).ready;
  lane2_tx_pll_lock_o <= tx_s_all_s(2).pll_lock;
  lane2_tx_status_o <= std_logic_vector(tx_s_all_s(2).status);
  lane2_rx_data_o <= std_logic_vector(rx_m_all_s(2).data(0));
  lane2_rx_aux_o <= std_logic_vector(rx_m_all_s(2).aux(0));
  lane2_rx_valid_o <= rx_m_all_s(2).valid;
  lane2_rx_pma_lock_o <= rx_m_all_s(2).pma_lock;
  lane2_rx_pcs_aligned_o <= rx_m_all_s(2).pcs_aligned;
  lane2_rx_elec_idle_o <= rx_m_all_s(2).elec_idle;
  lane2_rx_status_o <= std_logic_vector(rx_m_all_s(2).status);
  rx_s_all_s(2).ready <= lane2_rx_ready_i;
  rx_s_all_s(2).pcs_reset_n <= lane2_rx_pcs_reset_n_i;
  rx_s_all_s(2).align_trigger <= lane2_rx_align_trigger_i;
  rx_s_all_s(2).chbond_start <= lane2_rx_chbond_start_i;
  rx_s_all_s(2).control <= std_ulogic_vector(lane2_rx_control_i);

  -- Lane 3 ports
  lane_rx_all_s(3).p <= lane3_rxp;
  lane_rx_all_s(3).n <= lane3_rxn;
  lane3_txp <= lane_tx_all_s(3).p;
  lane3_txn <= lane_tx_all_s(3).n;
  lane3_clock_o <= lane_clock_all_s(3);
  lane3_reset_n_o <= lane_reset_n_all_s(3);
  pma_reset_n_all_s(3) <= lane3_pma_reset_n_i;

  tx_m_all_s(3).data <= (0 => std_ulogic_vector(lane3_tx_data_i), others => (others => '-'));
  tx_m_all_s(3).aux <= (0 => std_ulogic_vector(lane3_tx_aux_i), others => (others => '-'));
  tx_m_all_s(3).valid <= lane3_tx_valid_i;
  tx_m_all_s(3).pcs_reset_n <= lane3_tx_pcs_reset_n_i;
  tx_m_all_s(3).control <= std_ulogic_vector(lane3_tx_control_i);
  tx_m_all_s(3).control_h <= std_ulogic_vector(lane3_tx_control_h_i);
  tx_m_all_s(3).c2i_clock <= lane3_tx_c2i_clock_i;
  lane3_tx_ready_o <= tx_s_all_s(3).ready;
  lane3_tx_pll_lock_o <= tx_s_all_s(3).pll_lock;
  lane3_tx_status_o <= std_logic_vector(tx_s_all_s(3).status);
  lane3_rx_data_o <= std_logic_vector(rx_m_all_s(3).data(0));
  lane3_rx_aux_o <= std_logic_vector(rx_m_all_s(3).aux(0));
  lane3_rx_valid_o <= rx_m_all_s(3).valid;
  lane3_rx_pma_lock_o <= rx_m_all_s(3).pma_lock;
  lane3_rx_pcs_aligned_o <= rx_m_all_s(3).pcs_aligned;
  lane3_rx_elec_idle_o <= rx_m_all_s(3).elec_idle;
  lane3_rx_status_o <= std_logic_vector(rx_m_all_s(3).status);
  rx_s_all_s(3).ready <= lane3_rx_ready_i;
  rx_s_all_s(3).pcs_reset_n <= lane3_rx_pcs_reset_n_i;
  rx_s_all_s(3).align_trigger <= lane3_rx_align_trigger_i;
  rx_s_all_s(3).chbond_start <= lane3_rx_chbond_start_i;
  rx_s_all_s(3).control <= std_ulogic_vector(lane3_rx_control_i);

  lanes: for i in 0 to max_lane_count_c-1
  generate
    used: if i < lane_count_c
    generate
      lane_rx_s(i) <= lane_rx_all_s(i);
      lane_tx_all_s(i) <= lane_tx_s(i);
      lane_clock_all_s(i) <= lane_clock_s(i);
      pma_reset_n_s(i) <= pma_reset_n_all_s(i);
      tx_m_s(i) <= tx_m_all_s(i);
      tx_s_all_s(i) <= tx_s_s(i);
      rx_m_all_s(i) <= rx_m_s(i);
      rx_s_s(i) <= rx_s_all_s(i);

      -- tx_s.ready is not synchronous to the lane clock.
      reset_sync: nsl_clocking.async.async_edge
        port map(
          clock_i => lane_clock_s(i),
          data_i => tx_s_s(i).ready,
          data_o => lane_reset_n_all_s(i)
          );
    end generate;

    unused: if i >= lane_count_c
    generate
      lane_tx_all_s(i) <= (p => '0', n => '1');
      lane_clock_all_s(i) <= '0';
      lane_reset_n_all_s(i) <= '0';
      tx_s_all_s(i) <= (ready => '0', pll_lock => '0', status => (others => '0'));
      rx_m_all_s(i) <= (data => (others => (others => '0')),
                        aux => (others => (others => '0')),
                        valid => '0',
                        pma_lock => '0',
                        pcs_aligned => '0',
                        elec_idle => '0',
                        status => (others => '0'));
    end generate;
  end generate;

  cluster: nsl_transceiver.cluster.transceiver_cluster
    generic map(
      config_c => cluster_config_c,
      ref_clock_c => ref_clock_c
      )
    port map(
      reset_n_i => reset_n_i,
      ref_clock_i(0) => ref_clock_i,

      lane_tx_o => lane_tx_s,
      lane_rx_i => lane_rx_s,

      lane_tx_clock_o => lane_clock_s,
      lane_rx_clock_o => open,

      tx_m_i => tx_m_s,
      tx_s_o => tx_s_s,
      rx_m_o => rx_m_s,
      rx_s_i => rx_s_s,

      pma_reset_n_i => pma_reset_n_s,

      apb_clock_o => open,
      apb_reset_n_i => '1',
      apb_m_i => nsl_amba.apb.transfer_idle(nsl_amba.apb.config(8, 8)),
      apb_s_o => open
      );

end architecture;
