library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library hwdep;

entity ip_top is
  generic(
    tdata_num_bytes : natural range 1 to 32 := 4;
    usage_width : natural range 1 to 32 := 12;
    depth : natural range 1 to 65536 := 2048
    );
  port(
    s_aclk : in std_ulogic;
    s_aresetn : in std_ulogic;
    s_axis_tdata : in std_ulogic_vector(tdata_num_bytes*8-1 downto 0);
    s_axis_tlast : in std_ulogic;
    s_axis_tvalid : in std_ulogic;
    s_axis_tready : out std_ulogic;
    s_usage : out unsigned(usage_width-1 downto 0);

    m_aclk : in std_ulogic;
    m_aresetn : in std_ulogic;
    m_axis_tdata : out std_ulogic_vector(tdata_num_bytes*8-1 downto 0);
    m_axis_tlast : out std_ulogic;
    m_axis_tvalid : out std_ulogic;
    m_axis_tready : in std_ulogic;
    m_usage : out unsigned(usage_width-1 downto 0)
    );
end entity;

architecture rtl of ip_top is

  attribute X_INTERFACE_INFO : string;
  attribute X_INTERFACE_PARAMETER : string;

  attribute X_INTERFACE_INFO of s_axis_tready : signal is "xilinx.com:interface:axis:1.0 s_axis TREADY";
  attribute X_INTERFACE_INFO of s_axis_tvalid : signal is "xilinx.com:interface:axis:1.0 s_axis TVALID";
  attribute X_INTERFACE_INFO of s_axis_tlast : signal is "xilinx.com:interface:axis:1.0 s_axis TLAST";
  attribute X_INTERFACE_INFO of s_axis_tdata : signal is "xilinx.com:interface:axis:1.0 s_axis TDATA";
  attribute X_INTERFACE_PARAMETER of s_aclk : signal is "ASSOCIATED_BUSIF s_axis, ASSOCIATED_RESET s_aresetn";
  attribute X_INTERFACE_INFO of s_aresetn : signal is "xilinx.com:signal:reset:1.0 s_aresetn RST";
  attribute X_INTERFACE_PARAMETER of s_aresetn : signal is "POLARITY ACTIVE_LOW";

  attribute X_INTERFACE_INFO of m_axis_tready : signal is "xilinx.com:interface:axis:1.0 m_axis TREADY";
  attribute X_INTERFACE_INFO of m_axis_tvalid : signal is "xilinx.com:interface:axis:1.0 m_axis TVALID";
  attribute X_INTERFACE_INFO of m_axis_tlast : signal is "xilinx.com:interface:axis:1.0 m_axis TLAST";
  attribute X_INTERFACE_INFO of m_axis_tdata : signal is "xilinx.com:interface:axis:1.0 m_axis TDATA";
  attribute X_INTERFACE_PARAMETER of m_aclk : signal is "ASSOCIATED_BUSIF m_axis, ASSOCIATED_RESET m_aresetn";
  attribute X_INTERFACE_INFO of m_aresetn : signal is "xilinx.com:signal:reset:1.0 m_aresetn RST";
  attribute X_INTERFACE_PARAMETER of m_aresetn : signal is "POLARITY ACTIVE_LOW";

  signal async_resetn : std_ulogic;
  signal in_usage, out_usage : integer range 0 to depth;
  
begin

  async_resetn <= s_aresetn and m_aresetn;

  fifo: hwdep.fifo.fifo_2p
    generic map(
      depth => depth,
      data_width => tdata_num_bytes*8+1,
      clk_count => 2
      )
    port map(
      reset_n_i => async_resetn,
      clk_i(0) => s_aclk,
      clk_i(1) => m_aclk,

      out_data_o(tdata_num_bytes*8) => m_axis_tlast,
      out_data_o(tdata_num_bytes*8-1 downto 0) => m_axis_tdata,
      out_ready_i => m_axis_tready,
      out_valid_o => m_axis_tvalid,
      out_used_o => out_usage,
      
      in_data_i(tdata_num_bytes*8) => s_axis_tlast,
      in_data_i(tdata_num_bytes*8-1 downto 0) => s_axis_tdata,
      in_valid_i => s_axis_tvalid,
      in_ready_o => s_axis_tready,
      in_used_o => in_usage
      );

  m_usage <= to_unsigned(out_usage, usage_width);
  s_usage <= to_unsigned(in_usage, usage_width);
  
end;
