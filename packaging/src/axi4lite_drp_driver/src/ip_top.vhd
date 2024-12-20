library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_axi, nsl_data;
use nsl_axi.axi4_mm.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;

entity ip_top is
  generic(
    addr_size : natural := 12;
    drp_addr_width : natural := 9;
    drp_data_width : natural := 16
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
    s_axi_rdata : out std_logic_vector(31 downto 0);

    m_drp_addr : out std_logic_vector(drp_addr_width-1 downto 0);
    m_drp_en : out std_logic;
    m_drp_di : out std_logic_vector(drp_data_width-1 downto 0);
    m_drp_do : in std_logic_vector(drp_data_width-1 downto 0);
    m_drp_rdy : in std_logic;
    m_drp_we : out std_logic
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

  attribute X_INTERFACE_INFO of m_drp_addr : signal is "xilinx.com:interface:drp_rtl:1.0 m_drp DADDR";
  attribute X_INTERFACE_INFO of m_drp_en : signal is "xilinx.com:interface:drp_rtl:1.0 m_drp DEN";
  attribute X_INTERFACE_INFO of m_drp_di : signal is "xilinx.com:interface:drp_rtl:1.0 m_drp DI";
  attribute X_INTERFACE_INFO of m_drp_do : signal is "xilinx.com:interface:drp_rtl:1.0 m_drp DO";
  attribute X_INTERFACE_INFO of m_drp_rdy : signal is "xilinx.com:interface:drp_rtl:1.0 m_drp DRDY";
  attribute X_INTERFACE_INFO of m_drp_we : signal is "xilinx.com:interface:drp_rtl:1.0 m_drp DWE";

  
  attribute X_INTERFACE_PARAMETER of aclk : signal is "ASSOCIATED_BUSIF s_axi, ASSOCIATED_RESET aresetn";
  attribute X_INTERFACE_PARAMETER of aresetn : signal is "POLARITY ACTIVE_LOW";

  constant config_c : nsl_axi.axi4_mm.config_t := nsl_axi.axi4_mm.config(address_width => s_axi_araddr'length,
                                                                         data_bus_width => s_axi_wdata'length);
  signal axi_s : nsl_axi.axi4_mm.bus_t;
  
  signal reg_write_s, reg_read_s, reg_read_done_s, reg_write_ready_s, reg_pending_s, reg_enable_s : std_ulogic;
  signal reg_addr_s : unsigned(config_c.address_width-1 downto config_c.data_bus_width_l2);
  signal reg_wdata_s, reg_rdata_s : std_ulogic_vector(31 downto 0);
  signal reg_wbytes_s, reg_rbytes_s : byte_string(0 to 3);

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
  
  slave: nsl_axi.axi4_mm.axi4_mm_lite_slave
    generic map (
      config_c => config_c
      )
    port map (
      clock_i => aclk,
      reset_n_i => aresetn,

      axi_i => axi_s.m,
      axi_o => axi_s.s,

      address_o => reg_addr_s,

      w_data_o => reg_wbytes_s,
      w_ready_i => reg_write_ready_s,
      w_valid_o => reg_write_s,

      r_data_i => reg_rbytes_s,
      r_ready_o => reg_read_s,
      r_valid_i => reg_read_done_s
      );

  reg_wdata_s <= std_ulogic_vector(from_le(reg_wbytes_s));
  reg_rbytes_s <= to_le(unsigned(reg_rdata_s));

  reg_enable_s <= (reg_read_s or reg_write_s) and not reg_pending_s;

  read_done: process(aclk, aresetn)
  begin
    if rising_edge(aclk) then
      reg_pending_s <= reg_pending_s;

      reg_read_done_s <= m_drp_rdy;
      if reg_enable_s = '1' then
        reg_pending_s <= '1';
      end if;

      if m_drp_rdy = '1' then
        reg_pending_s <= '0';
      end if;
    end if;

    if aresetn = '0' then
      reg_read_done_s <= '0';
      reg_pending_s <= '0';
    end if;
  end process;
  
  m_drp_addr <= std_logic_vector(reg_addr_s(m_drp_addr'left+2 downto m_drp_addr'right+2));
  m_drp_en <= reg_enable_s;
  m_drp_di <= std_logic_vector(reg_wdata_s(m_drp_di'range));
  reg_rdata_s(reg_rdata_s'left downto m_drp_do'length) <= (others => '0');
  reg_rdata_s(m_drp_do'range) <= std_ulogic_vector(m_drp_do);
  m_drp_we <= reg_write_s;

end;
