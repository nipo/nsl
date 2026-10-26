library ieee;
use ieee.std_logic_1164.all;

library nsl_bnoc, nsl_mii;
use nsl_bnoc.committed.all;
use nsl_bnoc.framed.all;
use nsl_mii.sgmii.all;
use nsl_mii.link.all;

-- Vivado IP wrapper for nsl_mii.sgmii.sgmii_driver.
--
-- IP-XACT cannot express record ports, so the sgmii_m2p/sgmii_p2m 8B/10B
-- symbol interfaces are flattened to individual signals here, and the
-- committed links become two AXI4-Stream interfaces (matching
-- gmii_driver_ip_top's convention).
--
-- This is the protocol layer only: PCS TX/RX and clause-37
-- auto-negotiation, all in fabric logic, no pads. Wire the m2p_*_o/
-- p2m_*_i ports here to the matching m2p_*_i/p2m_*_o ports of a packaged
-- sgmii_adapter + transceiver_cluster_series7 (or any other backend
-- implementing the same sgmii_m2p/sgmii_p2m contract) to reach real pins. Both
-- wrappers share the m2p_*/p2m_* naming, so connecting them in the block
-- design is a same-name match, not a cross-reference exercise.
--
-- Auto-negotiation (IEEE 802.3 clause 37) is not optional: this driver
-- always runs it, fixed to full duplex / no pause / no next page. Both
-- ends of the link need a compliant SGMII/1000BASE-X peer; there is no
-- equivalent of a fixed configuration_vector bypass.

entity sgmii_driver_ip_top is
  generic(
    -- true: SGMII (config word 0x1801, link timer 1.6 ms).
    -- false: 1000BASE-X (config word 0x0020, link timer 10 ms).
    sgmii_mode : boolean := true
    );
  port(
    reset_n_i : in std_logic;
    clock_i   : in std_logic;

    -- 8B/10B symbol interface to the backend (sgmii_m2p, driver -> backend)
    m2p_data_o          : out std_logic_vector(7 downto 0);
    m2p_control_o       : out std_logic;
    m2p_tx_disparity_o  : out std_logic;
    m2p_align_rst_o     : out std_logic;
    m2p_valid_symbol_o  : out std_logic;

    -- 8B/10B symbol interface from the backend (sgmii_p2m, backend -> driver)
    p2m_data_i          : in std_logic_vector(7 downto 0);
    p2m_control_i       : in std_logic;
    p2m_code_err_i       : in std_logic;
    p2m_disparity_err_i  : in std_logic;
    p2m_align_ready_i    : in std_logic;
    p2m_clk_cor_i        : in std_logic := '0';

    -- SGMII speed encoding: 00=10M, 01=100M, 10=1G (default). Sampled by
    -- the driver as an ordinary input; there is no separate strobe like
    -- the Xilinx core's configuration_valid.
    link_speed_i : in std_logic_vector(1 downto 0) := "10";
    link_up_o    : out std_logic;

    -- Frames received from the link (driver rx_o), layer-1 format with FCS.
    from_mac_tdata  : out std_logic_vector(7 downto 0);
    from_mac_tvalid : out std_logic;
    from_mac_tlast  : out std_logic;
    from_mac_tready : in  std_logic;

    -- Frames to transmit on the link (driver tx_i), same format.
    to_mac_tdata  : in  std_logic_vector(7 downto 0);
    to_mac_tvalid : in  std_logic;
    to_mac_tlast  : in  std_logic;
    to_mac_tready : out std_logic
    );
end entity;

architecture beh of sgmii_driver_ip_top is

  attribute X_INTERFACE_INFO : string;
  attribute X_INTERFACE_PARAMETER : string;

  attribute X_INTERFACE_INFO of clock_i : signal is "xilinx.com:signal:clock:1.0 clock_i CLK";
  attribute X_INTERFACE_INFO of reset_n_i : signal is "xilinx.com:signal:reset:1.0 reset_n_i RST";
  attribute X_INTERFACE_PARAMETER of reset_n_i : signal is "POLARITY ACTIVE_LOW";
  attribute X_INTERFACE_PARAMETER of clock_i : signal is "ASSOCIATED_BUSIF sgmii:from_mac:to_mac, ASSOCIATED_RESET reset_n_i";

  attribute X_INTERFACE_INFO of from_mac_tdata : signal is "xilinx.com:interface:axis:1.0 from_mac TDATA";
  attribute X_INTERFACE_INFO of from_mac_tvalid : signal is "xilinx.com:interface:axis:1.0 from_mac TVALID";
  attribute X_INTERFACE_INFO of from_mac_tlast : signal is "xilinx.com:interface:axis:1.0 from_mac TLAST";
  attribute X_INTERFACE_INFO of from_mac_tready : signal is "xilinx.com:interface:axis:1.0 from_mac TREADY";

  attribute X_INTERFACE_INFO of to_mac_tdata : signal is "xilinx.com:interface:axis:1.0 to_mac TDATA";
  attribute X_INTERFACE_INFO of to_mac_tvalid : signal is "xilinx.com:interface:axis:1.0 to_mac TVALID";
  attribute X_INTERFACE_INFO of to_mac_tlast : signal is "xilinx.com:interface:axis:1.0 to_mac TLAST";
  attribute X_INTERFACE_INFO of to_mac_tready : signal is "xilinx.com:interface:axis:1.0 to_mac TREADY";

  -- sgmii_symbol bus, master side: the driver's sgmii_o/sgmii_i, grouped
  -- into a single pluggable BD connector the same way gmii_z7_phy_ip_top
  -- groups its gmii ports (bus definition nsl:interface:sgmii_symbol:1.0,
  -- abstraction nsl:interface:sgmii_symbol_rtl:1.0 -- Vivado resolves the
  -- abstraction from the bus VLNV given here, same as the xilinx.com:
  -- interface:axis:1.0/axis_rtl:1.0 pair used below for from_mac/to_mac --
  -- built from packaging/src/interface/sgmii_symbol). Instance name
  -- "sgmii" matches sgmii_adapter_ip_top's slave side, so
  -- the two wire up as a single connection in the canvas.
  attribute X_INTERFACE_INFO of m2p_data_o : signal is "nsl:interface:sgmii_symbol:1.0 sgmii m2p_data";
  attribute X_INTERFACE_INFO of m2p_control_o : signal is "nsl:interface:sgmii_symbol:1.0 sgmii m2p_control";
  attribute X_INTERFACE_INFO of m2p_tx_disparity_o : signal is "nsl:interface:sgmii_symbol:1.0 sgmii m2p_tx_disparity";
  attribute X_INTERFACE_INFO of m2p_align_rst_o : signal is "nsl:interface:sgmii_symbol:1.0 sgmii m2p_align_rst";
  attribute X_INTERFACE_INFO of m2p_valid_symbol_o : signal is "nsl:interface:sgmii_symbol:1.0 sgmii m2p_valid_symbol";

  attribute X_INTERFACE_INFO of p2m_data_i : signal is "nsl:interface:sgmii_symbol:1.0 sgmii p2m_data";
  attribute X_INTERFACE_INFO of p2m_control_i : signal is "nsl:interface:sgmii_symbol:1.0 sgmii p2m_control";
  attribute X_INTERFACE_INFO of p2m_code_err_i : signal is "nsl:interface:sgmii_symbol:1.0 sgmii p2m_code_err";
  attribute X_INTERFACE_INFO of p2m_disparity_err_i : signal is "nsl:interface:sgmii_symbol:1.0 sgmii p2m_disparity_err";
  attribute X_INTERFACE_INFO of p2m_align_ready_i : signal is "nsl:interface:sgmii_symbol:1.0 sgmii p2m_align_ready";
  attribute X_INTERFACE_INFO of p2m_clk_cor_i : signal is "nsl:interface:sgmii_symbol:1.0 sgmii p2m_clk_cor";

  signal sgmii_m2p_s : sgmii_m2p;
  signal sgmii_p2m_s : sgmii_p2m;

  signal rx_req_s : committed_req;
  signal rx_ack_s : committed_ack;
  signal tx_req_s : committed_req;
  signal tx_ack_s : committed_ack;

begin

  -- m2p (driver -> backend), flattened out of the record the driver drives.
  m2p_data_o         <= std_logic_vector(sgmii_m2p_s.data_m2p_symbol.data);
  m2p_control_o      <= sgmii_m2p_s.data_m2p_symbol.control;
  m2p_tx_disparity_o <= sgmii_m2p_s.tx_disparity;
  m2p_align_rst_o    <= sgmii_m2p_s.align_rst;
  m2p_valid_symbol_o <= sgmii_m2p_s.valid_symbol;

  -- p2m (backend -> driver), flattened into the record the driver reads.
  sgmii_p2m_s.data_p2m_symbol.data    <= std_ulogic_vector(p2m_data_i);
  sgmii_p2m_s.data_p2m_symbol.control <= p2m_control_i;
  sgmii_p2m_s.code_err                <= p2m_code_err_i;
  sgmii_p2m_s.disparity_err           <= p2m_disparity_err_i;
  sgmii_p2m_s.align_ready             <= p2m_align_ready_i;
  sgmii_p2m_s.clk_cor                 <= p2m_clk_cor_i;

  from_mac_tdata  <= std_logic_vector(rx_req_s.data);
  from_mac_tvalid <= rx_req_s.valid;
  from_mac_tlast  <= rx_req_s.last;
  rx_ack_s        <= framed_accept(from_mac_tready = '1');

  tx_req_s      <= framed_flit(data  => std_ulogic_vector(to_mac_tdata),
                               last  => to_mac_tlast = '1',
                               valid => to_mac_tvalid = '1');
  to_mac_tready <= tx_ack_s.ready;

  driver: nsl_mii.sgmii.sgmii_driver
    generic map(
      sgmii_mode => sgmii_mode
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i   => clock_i,

      sgmii_o => sgmii_m2p_s,
      sgmii_i => sgmii_p2m_s,

      link_speed_i => nsl_mii.link.to_speed(std_ulogic_vector(link_speed_i)),
      link_up_o    => link_up_o,

      rx_o => rx_req_s,
      rx_i => rx_ack_s,

      tx_i => tx_req_s,
      tx_o => tx_ack_s
      );

end architecture;
