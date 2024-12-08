library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_time, work;
use nsl_time.timestamp.all;

entity phc_main_flat is
  port(
    aclk : in std_ulogic;
    aresetn : in std_ulogic;

    s_config_awaddr : in std_logic_vector(5 downto 0);
    s_config_awvalid : in std_logic;
    s_config_awready : out std_logic;
    s_config_wdata : in std_logic_vector(31 downto 0);
    s_config_wstrb : in std_logic_vector(3 downto 0) := "1111";
    s_config_wvalid : in std_logic;
    s_config_wready : out std_logic;
    s_config_bready : in std_logic := '1';
    s_config_bvalid : out std_logic;
    s_config_bresp : out std_logic_vector(1 downto 0);
    s_config_araddr : in std_logic_vector(5 downto 0);
    s_config_arvalid : in std_logic;
    s_config_arready : out std_logic;
    s_config_rready : in std_logic := '1';
    s_config_rvalid : out std_logic;
    s_config_rresp : out std_logic_vector(1 downto 0);
    s_config_rdata : out std_logic_vector(31 downto 0);

    timestamp_second: out std_logic_vector(31 downto 0);
    timestamp_nanosecond: out std_logic_vector(29 downto 0);
    timestamp_abs_change: out std_logic
    );
end entity;

architecture rtl of phc_main_flat is

  attribute X_INTERFACE_INFO : string;
  attribute X_INTERFACE_PARAMETER : string;

  attribute X_INTERFACE_INFO of aclk : signal is "xilinx.com:signal:clock:1.0 aclk CLK";
  attribute X_INTERFACE_INFO of aresetn : signal is "xilinx.com:signal:reset:1.0 aresetn RST";

  attribute X_INTERFACE_INFO of s_config_awaddr : signal is "xilinx.com:interface:aximm:1.0 s_config AWADDR";
  attribute X_INTERFACE_INFO of s_config_awvalid : signal is "xilinx.com:interface:aximm:1.0 s_config AWVALID";
  attribute X_INTERFACE_INFO of s_config_awready : signal is "xilinx.com:interface:aximm:1.0 s_config AWREADY";
  attribute X_INTERFACE_INFO of s_config_wdata : signal is "xilinx.com:interface:aximm:1.0 s_config WDATA";
  attribute X_INTERFACE_INFO of s_config_wstrb : signal is "xilinx.com:interface:aximm:1.0 s_config WSTRB";
  attribute X_INTERFACE_INFO of s_config_wvalid : signal is "xilinx.com:interface:aximm:1.0 s_config WVALID";
  attribute X_INTERFACE_INFO of s_config_wready : signal is "xilinx.com:interface:aximm:1.0 s_config WREADY";
  attribute X_INTERFACE_INFO of s_config_bready : signal is "xilinx.com:interface:aximm:1.0 s_config BREADY";
  attribute X_INTERFACE_INFO of s_config_bvalid : signal is "xilinx.com:interface:aximm:1.0 s_config BVALID";
  attribute X_INTERFACE_INFO of s_config_bresp : signal is "xilinx.com:interface:aximm:1.0 s_config BRESP";
  attribute X_INTERFACE_INFO of s_config_araddr : signal is "xilinx.com:interface:aximm:1.0 s_config ARADDR";
  attribute X_INTERFACE_INFO of s_config_arvalid : signal is "xilinx.com:interface:aximm:1.0 s_config ARVALID";
  attribute X_INTERFACE_INFO of s_config_arready : signal is "xilinx.com:interface:aximm:1.0 s_config ARREADY";
  attribute X_INTERFACE_INFO of s_config_rready : signal is "xilinx.com:interface:aximm:1.0 s_config RREADY";
  attribute X_INTERFACE_INFO of s_config_rvalid : signal is "xilinx.com:interface:aximm:1.0 s_config RVALID";
  attribute X_INTERFACE_INFO of s_config_rresp : signal is "xilinx.com:interface:aximm:1.0 s_config RRESP";
  attribute X_INTERFACE_INFO of s_config_rdata : signal is "xilinx.com:interface:aximm:1.0 s_config RDATA";

  attribute X_INTERFACE_INFO of timestamp_second : signal is "nsl:interface:phc_timestamp:1.0 timestamp SECOND";
  attribute X_INTERFACE_INFO of timestamp_nanosecond : signal is "nsl:interface:phc_timestamp:1.0 timestamp NANOSECOND";
  attribute X_INTERFACE_INFO of timestamp_abs_change : signal is "nsl:interface:phc_timestamp:1.0 timestamp ABS_CHANGE";

  attribute X_INTERFACE_PARAMETER of aclk : signal is "ASSOCIATED_BUSIF s_config:m_worker, ASSOCIATED_RESET aresetn";
  attribute X_INTERFACE_PARAMETER of aresetn : signal is "POLARITY ACTIVE_LOW";

  signal s_config_i: nsl_amba.axi4_lite.a32_d32_ms;
  signal s_config_o: nsl_amba.axi4_lite.a32_d32_sm;
  signal s_timestamp_o: nsl_time.timestamp.timestamp_t;
  
begin

  s_config_awready <= s_config_o.awready;
  s_config_wready <= s_config_o.wready;
  s_config_bvalid <= s_config_o.bvalid;
  s_config_bresp <= std_logic_vector(s_config_o.bresp);
  s_config_arready <= s_config_o.arready;
  s_config_rvalid <= s_config_o.rvalid;
  s_config_rresp <= std_logic_vector(s_config_o.rresp);
  s_config_rdata <= std_logic_vector(s_config_o.rdata);

  s_config_i.awaddr(s_config_i.awaddr'left downto s_config_awaddr'left+1) <= (others => '0');
  s_config_i.awaddr(s_config_awaddr'range) <= std_ulogic_vector(s_config_awaddr);
  s_config_i.awvalid <= s_config_awvalid;
  s_config_i.wdata <= std_ulogic_vector(s_config_wdata);
  s_config_i.wstrb <= std_ulogic_vector(s_config_wstrb);
  s_config_i.wvalid <= s_config_wvalid;
  s_config_i.bready <= s_config_bready;
  s_config_i.araddr(s_config_i.araddr'left downto s_config_araddr'left+1) <= (others => '0');
  s_config_i.araddr(s_config_araddr'range) <= std_ulogic_vector(s_config_araddr);
  s_config_i.arvalid <= s_config_arvalid;
  s_config_i.rready <= s_config_rready;

  timestamp_nanosecond <= nanosecond_slv(s_timestamp_o);
  timestamp_second <= second_slv(s_timestamp_o);
  timestamp_abs_change <= abs_change_sl(s_timestamp_o);

  module: entity work.phc_main
    port map(
      aclk => aclk,
      aresetn => aresetn,

      config_i => s_config_i,
      config_o => s_config_o,

      timestamp_o => s_timestamp_o
      );

end;
