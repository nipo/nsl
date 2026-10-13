library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_mii, nsl_smi;
use nsl_bnoc.committed.all;
use nsl_bnoc.framed.all;
use nsl_mii.gmii.all;

-- Vivado IP wrapper for nsl_mii.gmii.gmii_z7_phy.
--
-- IP-XACT cannot express record ports, so the two gmii_io_group_t
-- groups become the ten signals of xilinx.com:interface:gmii:1.0, and
-- the committed links become two AXI4-Stream interfaces.
--
-- The block presents itself as a PHY to the MAC: it consumes TXD/TX_EN
-- and drives RXD/RX_DV, plus TX_CLK and RX_CLK.  Wire the gmii
-- interface straight to a Zynq-7 GMII_ETHERNET port.
--
-- With indep_rx_clock_c, frames to the MAC (to_mac, RXD/RX_DV, CRS
-- and RX_CLK) run on rx_clock_i, e.g. a clock recovered by an external
-- Phy, unrelated to clock_i. Otherwise everything runs on clock_i and
-- rx_clock_i is hidden by ports.tcl. to_mac is declared against
-- rx_clock_i; bd.tcl hands it clock_i's properties when rx_clock_i is
-- hidden.
--
-- With has_mdio_c, a fake MDIO PHY answers at phy_addr_c on the mdio
-- interface. It is the mirror of a Zynq-7 MDIO_ETHERNET_n EMIO port:
-- connect them straight together. link_up_i is reported in the status
-- register, mdio_resetn pulses low when the MAC sets the reset bit.
-- All of them are hidden by ports.tcl otherwise.

entity gmii_z7_phy_ip_top is
  generic(
    -- Inter-packet gap, in bit times.
    ipg_c : natural range 0 to 1023 := 96;
    -- Run to_mac and the GMII RX side on rx_clock_i.
    indep_rx_clock_c : boolean := false;
    -- Fake MDIO PHY.
    has_mdio_c : boolean := false;
    phy_addr_c : natural range 0 to 31 := 0
    );
  port(
    reset_n_i : in std_logic;
    clock_i   : in std_logic;
    -- Only used with indep_rx_clock_c.
    rx_clock_i : in std_logic := '0';

    gmii_txd    : in  std_logic_vector(7 downto 0);
    gmii_tx_en  : in  std_logic;
    gmii_tx_er  : in  std_logic;
    gmii_tx_clk : out std_logic;
    gmii_rxd    : out std_logic_vector(7 downto 0);
    gmii_rx_dv  : out std_logic;
    gmii_rx_er  : out std_logic;
    gmii_rx_clk : out std_logic;
    gmii_crs    : out std_logic;
    gmii_col    : out std_logic;

    -- Frames the MAC transmitted, layer-1 format with FCS.
    from_mac_tdata  : out std_logic_vector(7 downto 0);
    from_mac_tvalid : out std_logic;
    from_mac_tlast  : out std_logic;
    from_mac_tready : in  std_logic;

    -- Frames to hand to the MAC, same format.
    to_mac_tdata  : in  std_logic_vector(7 downto 0);
    to_mac_tvalid : in  std_logic;
    to_mac_tlast  : in  std_logic;
    to_mac_tready : out std_logic;

    -- Only used with has_mdio_c.
    mdio_mdc : in  std_logic := '1';
    mdio_o   : in  std_logic := '1';
    mdio_t   : in  std_logic := '1';
    mdio_i   : out std_logic;

    link_up_i   : in  std_logic := '0';
    mdio_resetn : out std_logic
    );
end entity;

architecture beh of gmii_z7_phy_ip_top is

  attribute X_INTERFACE_INFO : string;
  attribute X_INTERFACE_PARAMETER : string;

  attribute X_INTERFACE_INFO of clock_i : signal is "xilinx.com:signal:clock:1.0 clock_i CLK";
  attribute X_INTERFACE_INFO of reset_n_i : signal is "xilinx.com:signal:reset:1.0 reset_n_i RST";
  attribute X_INTERFACE_PARAMETER of reset_n_i : signal is "POLARITY ACTIVE_LOW";
  attribute X_INTERFACE_PARAMETER of clock_i : signal is "ASSOCIATED_BUSIF gmii:from_mac, ASSOCIATED_RESET reset_n_i";
  attribute X_INTERFACE_INFO of rx_clock_i : signal is "xilinx.com:signal:clock:1.0 rx_clock_i CLK";
  attribute X_INTERFACE_PARAMETER of rx_clock_i : signal is "ASSOCIATED_BUSIF to_mac";

  attribute X_INTERFACE_INFO of gmii_txd : signal is "xilinx.com:interface:gmii:1.0 gmii TXD";
  attribute X_INTERFACE_INFO of gmii_tx_en : signal is "xilinx.com:interface:gmii:1.0 gmii TX_EN";
  attribute X_INTERFACE_INFO of gmii_tx_er : signal is "xilinx.com:interface:gmii:1.0 gmii TX_ER";
  attribute X_INTERFACE_INFO of gmii_tx_clk : signal is "xilinx.com:interface:gmii:1.0 gmii TX_CLK";
  attribute X_INTERFACE_INFO of gmii_rxd : signal is "xilinx.com:interface:gmii:1.0 gmii RXD";
  attribute X_INTERFACE_INFO of gmii_rx_dv : signal is "xilinx.com:interface:gmii:1.0 gmii RX_DV";
  attribute X_INTERFACE_INFO of gmii_rx_er : signal is "xilinx.com:interface:gmii:1.0 gmii RX_ER";
  attribute X_INTERFACE_INFO of gmii_rx_clk : signal is "xilinx.com:interface:gmii:1.0 gmii RX_CLK";
  attribute X_INTERFACE_INFO of gmii_crs : signal is "xilinx.com:interface:gmii:1.0 gmii CRS";
  attribute X_INTERFACE_INFO of gmii_col : signal is "xilinx.com:interface:gmii:1.0 gmii COL";

  attribute X_INTERFACE_INFO of from_mac_tdata : signal is "xilinx.com:interface:axis:1.0 from_mac TDATA";
  attribute X_INTERFACE_INFO of from_mac_tvalid : signal is "xilinx.com:interface:axis:1.0 from_mac TVALID";
  attribute X_INTERFACE_INFO of from_mac_tlast : signal is "xilinx.com:interface:axis:1.0 from_mac TLAST";
  attribute X_INTERFACE_INFO of from_mac_tready : signal is "xilinx.com:interface:axis:1.0 from_mac TREADY";

  attribute X_INTERFACE_INFO of to_mac_tdata : signal is "xilinx.com:interface:axis:1.0 to_mac TDATA";
  attribute X_INTERFACE_INFO of to_mac_tvalid : signal is "xilinx.com:interface:axis:1.0 to_mac TVALID";
  attribute X_INTERFACE_INFO of to_mac_tlast : signal is "xilinx.com:interface:axis:1.0 to_mac TLAST";
  attribute X_INTERFACE_INFO of to_mac_tready : signal is "xilinx.com:interface:axis:1.0 to_mac TREADY";

  -- MDIO_ETHERNET_n is a master meant for an IOBUF, so the PHY side is
  -- its mirror: MDC, MDIO_O and MDIO_T in, MDIO_I out.
  attribute X_INTERFACE_MODE : string;
  attribute X_INTERFACE_MODE of mdio_mdc : signal is "mirroredMaster";
  attribute X_INTERFACE_INFO of mdio_mdc : signal is "xilinx.com:interface:mdio:1.0 mdio MDC";
  attribute X_INTERFACE_INFO of mdio_o : signal is "xilinx.com:interface:mdio:1.0 mdio MDIO_O";
  attribute X_INTERFACE_INFO of mdio_t : signal is "xilinx.com:interface:mdio:1.0 mdio MDIO_T";
  attribute X_INTERFACE_INFO of mdio_i : signal is "xilinx.com:interface:mdio:1.0 mdio MDIO_I";
  attribute X_INTERFACE_INFO of mdio_resetn : signal is "xilinx.com:signal:reset:1.0 mdio_resetn RST";
  attribute X_INTERFACE_PARAMETER of mdio_resetn : signal is "POLARITY ACTIVE_LOW";

  signal tx_s, rx_s : gmii_io_group_t;
  signal from_mac_req_s : committed_req;
  signal from_mac_ack_s : committed_ack;
  signal to_mac_req_s : committed_req;
  signal to_mac_ack_s : committed_ack;
  signal smi_i_s : nsl_smi.smi.smi_slave_i;
  signal smi_o_s : nsl_smi.smi.smi_slave_o;
  signal mdio_line_s : std_ulogic;

begin

  tx_s.data <= std_ulogic_vector(gmii_txd);
  tx_s.en   <= gmii_tx_en;
  tx_s.er   <= gmii_tx_er;

  gmii_rxd   <= std_logic_vector(rx_s.data);
  gmii_rx_dv <= rx_s.en;
  gmii_rx_er <= rx_s.er;

  from_mac_tdata  <= std_logic_vector(from_mac_req_s.data);
  from_mac_tvalid <= from_mac_req_s.valid;
  from_mac_tlast  <= from_mac_req_s.last;
  from_mac_ack_s  <= framed_accept(from_mac_tready = '1');

  to_mac_req_s  <= framed_flit(data  => std_ulogic_vector(to_mac_tdata),
                               last  => to_mac_tlast = '1',
                               valid => to_mac_tvalid = '1');
  to_mac_tready <= to_mac_ack_s.ready;

  -- MAC and PHY share the line, with a pull-up.
  mdio_line_s <= mdio_o when mdio_t = '0'
                 else smi_o_s.mdio.v when smi_o_s.mdio.output = '1'
                 else '1';
  mdio_i <= mdio_line_s;
  smi_i_s.mdc <= mdio_mdc;
  smi_i_s.mdio <= mdio_line_s;

  phy: nsl_mii.gmii.gmii_z7_phy
    generic map(
      ipg_c => ipg_c,
      indep_rx_clock_c => indep_rx_clock_c,
      has_mdio_c => has_mdio_c,
      phy_addr_c => to_unsigned(phy_addr_c, 5)
      )
    port map(
      reset_n_i  => reset_n_i,
      clock_i    => clock_i,
      rx_clock_i => rx_clock_i,

      gmii_tx_i     => tx_s,
      gmii_tx_clk_o => gmii_tx_clk,
      gmii_col_o    => gmii_col,
      gmii_crs_o    => gmii_crs,
      gmii_rx_clk_o => gmii_rx_clk,
      gmii_rx_o     => rx_s,

      from_mac_o => from_mac_req_s,
      from_mac_i => from_mac_ack_s,

      to_mac_i => to_mac_req_s,
      to_mac_o => to_mac_ack_s,

      smi_i => smi_i_s,
      smi_o => smi_o_s,

      link_up_i   => link_up_i,
      mdio_resetn => mdio_resetn
      );

end architecture;
