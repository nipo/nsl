library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_coresight, nsl_axi, nsl_clocking;

entity swd_axi4lite_master is
  generic(
    rom_base : unsigned(31 downto 0) := x"00000000";
    dp_idr : unsigned(31 downto 0) := X"0ba00477"; 
    ap_idr : unsigned(31 downto 0) := X"04770004"
    );
  port(
    aclk : in std_logic;
    aresetn : in std_logic;

    m_axi_awaddr : out std_logic_vector(31 downto 0);
    m_axi_awvalid : out std_logic;
    m_axi_awready : in std_logic;
    m_axi_wdata : out std_logic_vector(31 downto 0);
    m_axi_wstrb : out std_logic_vector(3 downto 0);
    m_axi_wvalid : out std_logic;
    m_axi_wready : in std_logic;
    m_axi_bready : out std_logic;
    m_axi_bvalid : in std_logic;
    m_axi_bresp : in std_logic_vector(1 downto 0);
    m_axi_araddr : out std_logic_vector(31 downto 0);
    m_axi_arvalid : out std_logic;
    m_axi_arready : in std_logic;
    m_axi_rready : out std_logic;
    m_axi_rvalid : in std_logic;
    m_axi_rresp : in std_logic_vector(1 downto 0);
    m_axi_rdata : in std_logic_vector(31 downto 0);

    swclk : in std_logic;
    swdio_i : in std_logic;
    -- Active low enable
    swdio_t : out std_logic;
    swdio_o : out std_logic
    );
end entity;

architecture rtl of swd_axi4lite_master is

  -- attributes for ports should be in entity block, and case is supposed to be
  -- non-sensitive, but Xilinx tools only take upper-cased names attributes,
  -- and only if they are inside the architecture block... Go figure.
  attribute X_INTERFACE_INFO : string;
  attribute X_INTERFACE_PARAMETER : string;

  attribute X_INTERFACE_INFO of m_axi_awaddr : signal is "xilinx.com:interface:aximm:1.0 m_axi AWADDR";
  attribute X_INTERFACE_INFO of m_axi_awvalid : signal is "xilinx.com:interface:aximm:1.0 m_axi AWVALID";
  attribute X_INTERFACE_INFO of m_axi_awready : signal is "xilinx.com:interface:aximm:1.0 m_axi AWREADY";
  attribute X_INTERFACE_INFO of m_axi_wdata : signal is "xilinx.com:interface:aximm:1.0 m_axi WDATA";
  attribute X_INTERFACE_INFO of m_axi_wstrb : signal is "xilinx.com:interface:aximm:1.0 m_axi WSTRB";
  attribute X_INTERFACE_INFO of m_axi_wvalid : signal is "xilinx.com:interface:aximm:1.0 m_axi WVALID";
  attribute X_INTERFACE_INFO of m_axi_wready : signal is "xilinx.com:interface:aximm:1.0 m_axi WREADY";
  attribute X_INTERFACE_INFO of m_axi_bready : signal is "xilinx.com:interface:aximm:1.0 m_axi BREADY";
  attribute X_INTERFACE_INFO of m_axi_bvalid : signal is "xilinx.com:interface:aximm:1.0 m_axi BVALID";
  attribute X_INTERFACE_INFO of m_axi_bresp : signal is "xilinx.com:interface:aximm:1.0 m_axi BRESP";
  attribute X_INTERFACE_INFO of m_axi_araddr : signal is "xilinx.com:interface:aximm:1.0 m_axi ARADDR";
  attribute X_INTERFACE_INFO of m_axi_arvalid : signal is "xilinx.com:interface:aximm:1.0 m_axi ARVALID";
  attribute X_INTERFACE_INFO of m_axi_arready : signal is "xilinx.com:interface:aximm:1.0 m_axi ARREADY";
  attribute X_INTERFACE_INFO of m_axi_rready : signal is "xilinx.com:interface:aximm:1.0 m_axi RREADY";
  attribute X_INTERFACE_INFO of m_axi_rvalid : signal is "xilinx.com:interface:aximm:1.0 m_axi RVALID";
  attribute X_INTERFACE_INFO of m_axi_rresp : signal is "xilinx.com:interface:aximm:1.0 m_axi RRESP";
  attribute X_INTERFACE_INFO of m_axi_rdata : signal is "xilinx.com:interface:aximm:1.0 m_axi RDATA";

  attribute X_INTERFACE_PARAMETER of aclk : signal is "ASSOCIATED_BUSIF m_axi, ASSOCIATED_RESET aresetn";
  attribute X_INTERFACE_PARAMETER of aresetn : signal is "POLARITY ACTIVE_LOW";

  attribute X_INTERFACE_INFO of swclk   : signal is "nsl:interface:swd:1.0 swd clk";
  attribute X_INTERFACE_INFO of swdio_t : signal is "nsl:interface:swd:1.0 swd dio_t";
  attribute X_INTERFACE_INFO of swdio_o : signal is "nsl:interface:swd:1.0 swd dio_o";
  attribute X_INTERFACE_INFO of swdio_i : signal is "nsl:interface:swd:1.0 swd dio_i";

  signal swd_bus : nsl_coresight.swd.swd_slave_bus;
  signal dapbus_gen, dapbus_memap : nsl_coresight.dapbus.dapbus_bus;
  signal mem_bus : nsl_axi.axi4_lite.a32_d32;
  signal ctrl, ctrl_w, stat :std_ulogic_vector(31 downto 0);

  signal awaddr : std_ulogic_vector(31 downto 0);
  signal wdata : std_ulogic_vector(31 downto 0);
  signal wstrb : std_ulogic_vector(3 downto 0);
  signal araddr : std_ulogic_vector(31 downto 0);

begin

  swdio_t <= not swd_bus.o.dio.output;
  swdio_o <= swd_bus.o.dio.v;
  swd_bus.i.dio <= swdio_i;

  deglitcher: nsl_clocking.async.async_deglitcher
    port map(
      clock_i => aclk,
      data_i => swclk,
      data_o => swd_bus.i.clk
      );
  
  dp: nsl_coresight.dp.swdp
    generic map(
      idr => dp_idr
      )
    port map(
      swd_i => swd_bus.i,
      swd_o => swd_bus.o,

      dap_o => dapbus_gen.ms,
      dap_i => dapbus_gen.sm,

      ctrl_o => ctrl,

      stat_i => stat,

      abort_o => open
      );

  stat_update: process(ctrl)
  begin
    stat <= ctrl;
    stat(27) <= ctrl(26);
    stat(29) <= ctrl(28);
    stat(31) <= ctrl(30);
  end process;
  
  interconnect: nsl_coresight.dapbus.dapbus_interconnect
    generic map(
      access_port_count => 1
      )
    port map(
      s_i => dapbus_gen.ms,
      s_o => dapbus_gen.sm,

      m_i(0) => dapbus_memap.sm,
      m_o(0) => dapbus_memap.ms
      );

  mem_ap: nsl_coresight.ap.axi4_lite_a32_d32_ap
    generic map(
      rom_base => rom_base,
      idr => ap_idr
      )
    port map(
      clk_i => aclk,
      reset_n_i => aresetn,

      dbgen_i => ctrl(28),
      spiden_i => '1',

      dap_i => dapbus_memap.ms,
      dap_o => dapbus_memap.sm,

      mem_o.awaddr(31 downto 0) => awaddr,
      mem_o.awvalid => m_axi_awvalid,
      mem_o.wdata => wdata,
      mem_o.wstrb => wstrb,
      mem_o.wvalid => m_axi_wvalid,
      mem_o.bready => m_axi_bready,
      mem_o.araddr(31 downto 0) => araddr,
      mem_o.arvalid => m_axi_arvalid,
      mem_o.rready => m_axi_rready,

      mem_i.awready => m_axi_awready,
      mem_i.wready => m_axi_wready,
      mem_i.bvalid => m_axi_bvalid,
      mem_i.bresp => std_ulogic_vector(m_axi_bresp),
      mem_i.arready => m_axi_arready,
      mem_i.rvalid => m_axi_rvalid,
      mem_i.rresp => std_ulogic_vector(m_axi_rresp),
      mem_i.rdata => std_ulogic_vector(m_axi_rdata)
      );

  m_axi_awaddr <= std_logic_vector(awaddr);
  m_axi_araddr <= std_logic_vector(araddr);
  m_axi_wdata <= std_logic_vector(wdata);
  m_axi_wstrb <= std_logic_vector(wstrb);
  
end;
