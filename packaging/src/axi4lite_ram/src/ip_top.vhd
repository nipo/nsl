library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_axi, nsl_data;

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
  
  constant config_c : nsl_axi.axi4_mm.config_t := nsl_axi.axi4_mm.config(address_width => s_axi_araddr'length,
                                                                         data_bus_width => s_axi_wdata'length);
  signal axi_s : nsl_axi.axi4_mm.bus_t;
  

begin

  packer: nsl_axi.packer.axi4_mm_lite_slave_packer
    generic map(
      config_c => config_c
      )
    port map(
      awaddr => s_axi_awaddr,
      awvalid => s_axi_awvalid,
      awready => s_axi_awready,
      wdata => s_axi_wdata,
      wstrb => s_axi_wstrb,
      wvalid => s_axi_wvalid,
      wready => s_axi_wready,
      bready => s_axi_bready,
      bvalid => s_axi_bvalid,
      bresp => s_axi_bresp,
      araddr => s_axi_araddr,
      arvalid => s_axi_arvalid,
      arready => s_axi_arready,
      rready => s_axi_rready,
      rvalid => s_axi_rvalid,
      rresp => s_axi_rresp,
      rdata => s_axi_rdata,

      axi_o => axi_s.m,
      axi_i => axi_s.s
      );

  impl: nsl_axi.ram.axi4_mm_lite_ram
    generic map(
      config_c => config_c,
      byte_size_l2_c => addr_size
      )
    port map (
      clock_i => aclk,
      reset_n_i => aresetn,

      axi_i => axi_s.m,
      axi_o => axi_s.s
      );

end;
