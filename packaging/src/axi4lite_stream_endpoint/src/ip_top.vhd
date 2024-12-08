library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_logic;
use nsl_logic.bool.all;
use nsl_amba.axi4_mm.all;
use nsl_amba.axi4_stream.all;

entity ip_top is
  generic(
    addr_size : natural := 8;
    stream_byte_count : natural range 1 to 3 := 1;
    tx_buffer_depth: natural range 4 to 4096 := 1024;
    rx_buffer_depth: natural range 4 to 4096 := 1024
    );
  port(
    aclk    : in  std_logic;
    aresetn : in  std_logic;

    irq : out std_logic;
    
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
    s_axi_rdata : out std_logic_vector(31 downto 0);

    m_axis_tdata : out std_logic_vector(stream_byte_count*8-1 downto 0);
    m_axis_tvalid : out std_logic;
    m_axis_tlast : out std_logic;
    m_axis_tready : in std_logic;

    s_axis_tdata : in std_logic_vector(stream_byte_count*8-1 downto 0);
    s_axis_tvalid : in std_logic;
    s_axis_tlast : in std_logic;
    s_axis_tready : out std_logic
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

  attribute X_INTERFACE_INFO of irq : signal is "xilinx.com:signal:interrupt:1.0 irq INTERRUPT";
  attribute X_INTERFACE_PARAMETER of irq : signal is "SENSITIVITY LEVEL_HIGH";
  
  attribute X_INTERFACE_INFO of m_axis_tready : signal is "xilinx.com:interface:axis:1.0 m_axis TREADY";
  attribute X_INTERFACE_INFO of m_axis_tvalid : signal is "xilinx.com:interface:axis:1.0 m_axis TVALID";
  attribute X_INTERFACE_INFO of m_axis_tlast : signal is "xilinx.com:interface:axis:1.0 m_axis TLAST";
  attribute X_INTERFACE_INFO of m_axis_tdata : signal is "xilinx.com:interface:axis:1.0 m_axis TDATA";

  attribute X_INTERFACE_INFO of s_axis_tready : signal is "xilinx.com:interface:axis:1.0 s_axis TREADY";
  attribute X_INTERFACE_INFO of s_axis_tvalid : signal is "xilinx.com:interface:axis:1.0 s_axis TVALID";
  attribute X_INTERFACE_INFO of s_axis_tlast : signal is "xilinx.com:interface:axis:1.0 s_axis TLAST";
  attribute X_INTERFACE_INFO of s_axis_tdata : signal is "xilinx.com:interface:axis:1.0 s_axis TDATA";

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

  attribute X_INTERFACE_PARAMETER of aclk : signal is "ASSOCIATED_BUSIF s_axi,s_axis,m_axis ASSOCIATED_RESET aresetn";
  attribute X_INTERFACE_PARAMETER of aresetn : signal is "POLARITY ACTIVE_LOW";
  
  constant mm_config_c : nsl_amba.axi4_mm.config_t := nsl_amba.axi4_mm.config(address_width => s_axi_araddr'length,
                                                                         data_bus_width => s_axi_wdata'length);
  constant stream_config_c : nsl_amba.axi4_stream.config_t := nsl_amba.axi4_stream.config(bytes => stream_byte_count);

  signal axi_s : nsl_amba.axi4_mm.bus_t;
  signal tx_s, rx_s: nsl_amba.axi4_stream.bus_t;

  signal irq_n_s : std_ulogic;
  
begin

  packer: nsl_amba.packer.axi4_mm_lite_slave_packer
    generic map(
      config_c => mm_config_c
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

  impl: nsl_amba.stream_endpoint.axi4_stream_endpoint_lite
    generic map(
      mm_config_c => mm_config_c,
      stream_config_c => stream_config_c,
      out_buffer_depth_c => tx_buffer_depth,
      in_buffer_depth_c => rx_buffer_depth
      )
    port map (
      clock_i => aclk,
      reset_n_i => aresetn,

      irq_n_o => irq_n_s,
      
      mm_i => axi_s.m,
      mm_o => axi_s.s,

      rx_i => rx_s.m,
      rx_o => rx_s.s,

      tx_o => tx_s.m,
      tx_i => tx_s.s
      );

  irq <= not irq_n_s;
  
  m_axis_tdata <= std_logic_vector(value(stream_config_c, tx_s.m));
  m_axis_tvalid <= to_logic(is_valid(stream_config_c, tx_s.m));
  m_axis_tlast <= to_logic(is_last(stream_config_c, tx_s.m));
  tx_s.s <= accept(stream_config_c, ready => m_axis_tready = '1');

  s_axis_tready <= to_logic(is_ready(stream_config_c, rx_s.s));
  rx_s.m <= transfer(stream_config_c,
                     value => unsigned(s_axis_tdata),
                     valid => s_axis_tvalid = '1',
                     last => s_axis_tlast = '1');
  
end;
