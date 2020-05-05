library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_axi;

entity ip_top is
  generic(
    addr_size : natural := 12
    );
  port(
    aclk    : in  std_logic;
    aresetn : in  std_logic;

    s_axi_awaddr : in std_logic_vector(addr_size-1 downto 0);
    s_axi_awvalid : in std_logic;
    s_axi_awready : out std_logic;
    s_axi_wdata : in std_logic_vector(31 downto 0);
    s_axi_wstrb : in std_logic_vector(3 downto 0) := "1111";
    s_axi_wvalid : in std_logic;
    s_axi_wready : out std_logic;
    s_axi_bready : in std_logic := '1';
    s_axi_bvalid : out std_logic;
    s_axi_bresp : out std_logic_vector(1 downto 0);
    s_axi_araddr : in std_logic_vector(addr_size-1 downto 0);
    s_axi_arvalid : in std_logic;
    s_axi_arready : out std_logic;
    s_axi_rready : in std_logic := '1';
    s_axi_rvalid : out std_logic;
    s_axi_rresp : out std_logic_vector(1 downto 0);
    s_axi_rdata : out std_logic_vector(31 downto 0)
    );
end entity;

architecture rtl of ip_top is

  -- attributes for ports should be in entity block, and case is supposed to be
  -- non-sensitive, but Xilinx tools only take upper-cased names attributes,
  -- and only if they are inside the architecture block... Go figure.
  attribute X_INTERFACE_INFO : string;
  attribute X_INTERFACE_PARAMETER : string;

  attribute X_INTERFACE_INFO of aclk : signal is "xilinx.com:signal:clock:1.0 aclk CLK";
  attribute X_INTERFACE_INFO of aresetn : signal is "xilinx.com:signal:reset:1.0 aresetn RST";

  attribute X_INTERFACE_INFO of s_axi_awaddr : signal is "xilinx.com:interface:aximm:1.0 s_axi AWADDR";
  attribute X_INTERFACE_INFO of s_axi_awvalid : signal is "xilinx.com:interface:aximm:1.0 s_axi AWVALID";
  attribute X_INTERFACE_INFO of s_axi_awready : signal is "xilinx.com:interface:aximm:1.0 s_axi AWREADY";
  attribute X_INTERFACE_INFO of s_axi_wdata : signal is "xilinx.com:interface:aximm:1.0 s_axi WDATA";
  attribute X_INTERFACE_INFO of s_axi_wstrb : signal is "xilinx.com:interface:aximm:1.0 s_axi WSTRB";
  attribute X_INTERFACE_INFO of s_axi_wvalid : signal is "xilinx.com:interface:aximm:1.0 s_axi WVALID";
  attribute X_INTERFACE_INFO of s_axi_wready : signal is "xilinx.com:interface:aximm:1.0 s_axi WREADY";
  attribute X_INTERFACE_INFO of s_axi_bready : signal is "xilinx.com:interface:aximm:1.0 s_axi BREADY";
  attribute X_INTERFACE_INFO of s_axi_bvalid : signal is "xilinx.com:interface:aximm:1.0 s_axi BVALID";
  attribute X_INTERFACE_INFO of s_axi_bresp : signal is "xilinx.com:interface:aximm:1.0 s_axi BRESP";
  attribute X_INTERFACE_INFO of s_axi_araddr : signal is "xilinx.com:interface:aximm:1.0 s_axi ARADDR";
  attribute X_INTERFACE_INFO of s_axi_arvalid : signal is "xilinx.com:interface:aximm:1.0 s_axi ARVALID";
  attribute X_INTERFACE_INFO of s_axi_arready : signal is "xilinx.com:interface:aximm:1.0 s_axi ARREADY";
  attribute X_INTERFACE_INFO of s_axi_rready : signal is "xilinx.com:interface:aximm:1.0 s_axi RREADY";
  attribute X_INTERFACE_INFO of s_axi_rvalid : signal is "xilinx.com:interface:aximm:1.0 s_axi RVALID";
  attribute X_INTERFACE_INFO of s_axi_rresp : signal is "xilinx.com:interface:aximm:1.0 s_axi RRESP";
  attribute X_INTERFACE_INFO of s_axi_rdata : signal is "xilinx.com:interface:aximm:1.0 s_axi RDATA";

  attribute X_INTERFACE_PARAMETER of aclk : signal is "ASSOCIATED_BUSIF s_axi, ASSOCIATED_RESET aresetn";
  attribute X_INTERFACE_PARAMETER of aresetn : signal is "POLARITY ACTIVE_LOW";

  signal bresp, rresp : std_ulogic_vector(1 downto 0);
  signal rdata : std_ulogic_vector(31 downto 0);
  
begin
  
  mem: nsl_axi.bram.axi4_lite_a32_d32_ram
    generic map (
      mem_size_log2_c => addr_size
      )
    port map (
      clock_i => aclk,
      reset_n_i => aresetn,

      axi_i.awaddr(31 downto addr_size) => (others => '0'),
      axi_i.awaddr(addr_size-1 downto 0) => std_ulogic_vector(s_axi_awaddr),
      axi_i.awvalid => s_axi_awvalid,
      axi_i.wdata => std_ulogic_vector(s_axi_wdata),
      axi_i.wstrb => std_ulogic_vector(s_axi_wstrb),
      axi_i.wvalid => s_axi_wvalid,
      axi_i.bready => s_axi_bready,
      axi_i.araddr(31 downto addr_size) => (others => '0'),
      axi_i.araddr(addr_size-1 downto 0) => std_ulogic_vector(s_axi_araddr),
      axi_i.arvalid => s_axi_arvalid,
      axi_i.rready => s_axi_rready,

      axi_o.awready => s_axi_awready,
      axi_o.wready => s_axi_wready,
      axi_o.bvalid => s_axi_bvalid,
      axi_o.bresp => bresp,
      axi_o.arready => s_axi_arready,
      axi_o.rvalid => s_axi_rvalid,
      axi_o.rresp => rresp,
      axi_o.rdata => rdata
      );

  s_axi_bresp <= std_logic_vector(bresp);
  s_axi_rresp <= std_logic_vector(rresp);
  s_axi_rdata <= std_logic_vector(rdata);
  
end;
