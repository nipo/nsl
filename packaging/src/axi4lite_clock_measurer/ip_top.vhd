library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_clocking;

entity ip_top is
  generic(
    aclk_rate : integer := 100e6;
    clock_count : integer range 1 to 16 := 1;
    update_hz_l2 : integer := 5;
    max_hz_l2 : integer := 28
    );
  port(
    aclk    : in  std_logic;
    aresetn : in  std_logic;

    s_axi_awaddr : in std_logic_vector(7 downto 0);
    s_axi_awvalid : in std_logic;
    s_axi_awready : out std_logic;
    s_axi_wdata : in std_logic_vector(31 downto 0);
    s_axi_wstrb : in std_logic_vector(3 downto 0) := "1111";
    s_axi_wvalid : in std_logic;
    s_axi_wready : out std_logic;
    s_axi_bready : in std_logic := '1';
    s_axi_bvalid : out std_logic;
    s_axi_bresp : out std_logic_vector(1 downto 0);
    s_axi_araddr : in std_logic_vector(7 downto 0);
    s_axi_arvalid : in std_logic;
    s_axi_arready : out std_logic;
    s_axi_rready : in std_logic := '1';
    s_axi_rvalid : out std_logic;
    s_axi_rresp : out std_logic_vector(1 downto 0);
    s_axi_rdata : out std_logic_vector(31 downto 0);

    measured_clock_0  : in std_logic;
    measured_clock_1  : in std_logic := '0';
    measured_clock_2  : in std_logic := '0';
    measured_clock_3  : in std_logic := '0';
    measured_clock_4  : in std_logic := '0';
    measured_clock_5  : in std_logic := '0';
    measured_clock_6  : in std_logic := '0';
    measured_clock_7  : in std_logic := '0';
    measured_clock_8  : in std_logic := '0';
    measured_clock_9  : in std_logic := '0';
    measured_clock_10 : in std_logic := '0';
    measured_clock_11 : in std_logic := '0';
    measured_clock_12 : in std_logic := '0';
    measured_clock_13 : in std_logic := '0';
    measured_clock_14 : in std_logic := '0';
    measured_clock_15 : in std_logic := '0'
    );
end entity;

architecture rtl of ip_top is

  constant addr_size : integer := s_axi_awaddr'left + 1;
  
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

  attribute X_INTERFACE_INFO of measured_clock_0  : signal is "xilinx.com:signal:clock:1.0 measured_clock_0  CLK";
  attribute X_INTERFACE_INFO of measured_clock_1  : signal is "xilinx.com:signal:clock:1.0 measured_clock_1  CLK";
  attribute X_INTERFACE_INFO of measured_clock_2  : signal is "xilinx.com:signal:clock:1.0 measured_clock_2  CLK";
  attribute X_INTERFACE_INFO of measured_clock_3  : signal is "xilinx.com:signal:clock:1.0 measured_clock_3  CLK";
  attribute X_INTERFACE_INFO of measured_clock_4  : signal is "xilinx.com:signal:clock:1.0 measured_clock_4  CLK";
  attribute X_INTERFACE_INFO of measured_clock_5  : signal is "xilinx.com:signal:clock:1.0 measured_clock_5  CLK";
  attribute X_INTERFACE_INFO of measured_clock_6  : signal is "xilinx.com:signal:clock:1.0 measured_clock_6  CLK";
  attribute X_INTERFACE_INFO of measured_clock_7  : signal is "xilinx.com:signal:clock:1.0 measured_clock_7  CLK";
  attribute X_INTERFACE_INFO of measured_clock_8  : signal is "xilinx.com:signal:clock:1.0 measured_clock_8  CLK";
  attribute X_INTERFACE_INFO of measured_clock_9  : signal is "xilinx.com:signal:clock:1.0 measured_clock_9  CLK";
  attribute X_INTERFACE_INFO of measured_clock_10 : signal is "xilinx.com:signal:clock:1.0 measured_clock_10 CLK";
  attribute X_INTERFACE_INFO of measured_clock_11 : signal is "xilinx.com:signal:clock:1.0 measured_clock_11 CLK";
  attribute X_INTERFACE_INFO of measured_clock_12 : signal is "xilinx.com:signal:clock:1.0 measured_clock_12 CLK";
  attribute X_INTERFACE_INFO of measured_clock_13 : signal is "xilinx.com:signal:clock:1.0 measured_clock_13 CLK";
  attribute X_INTERFACE_INFO of measured_clock_14 : signal is "xilinx.com:signal:clock:1.0 measured_clock_14 CLK";
  attribute X_INTERFACE_INFO of measured_clock_15 : signal is "xilinx.com:signal:clock:1.0 measured_clock_15 CLK";

  constant config_c : nsl_amba.axi4_mm.config_t := nsl_amba.axi4_mm.config(address_width => s_axi_araddr'length,
                                                                         data_bus_width => s_axi_wdata'length);
  signal axi_s : nsl_amba.axi4_mm.bus_t;
  
  subtype rate_t is unsigned(max_hz_l2-1 downto 0);
  type rate_vector is array(integer range <>) of rate_t;

  signal measured_clock_s : std_ulogic_vector(0 to 15);
  signal rate_s : rate_vector(0 to clock_count-1);

  signal reg_no_s: natural range 0 to 15;
  signal r_value_s : unsigned(31 downto 0);

begin

  packer: nsl_amba.packer.axi4_mm_lite_slave_packer
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
  
  mem: nsl_amba.axi4_mm.axi4_mm_lite_regmap
    generic map (
      config_c => config_c,
      reg_count_l2_c => 4
      )
    port map (
      clock_i => aclk,
      reset_n_i => aresetn,

      axi_i => axi_s.m,
      axi_o => axi_s.s,

      reg_no_o => reg_no_s,
      r_value_i => r_value_s
      );

  updater: process(reg_no_s, rate_s) is
  begin
    r_value_s <= (others => '0');

    for i in 0 to clock_count-1
    loop
      if i = reg_no_s then
        r_value_s <= resize(rate_s(i), r_value_s'length);
      end if;
    end loop;
  end process;

  measurer: for i in 0 to clock_count-1
  generate
    m: nsl_clocking.interdomain.clock_rate_measurer
      generic map(
        clock_i_hz_c => aclk_rate,
        update_hz_l2_c => update_hz_l2
        )
      port map(
        clock_i => aclk,
        reset_n_i => aresetn,

        measured_clock_i => measured_clock_s(i),
        rate_hz_o => rate_s(i)
        );
  end generate;

  measured_clock_s(0) <= measured_clock_0;
  measured_clock_s(1) <= measured_clock_1;
  measured_clock_s(2) <= measured_clock_2;
  measured_clock_s(3) <= measured_clock_3;
  measured_clock_s(4) <= measured_clock_4;
  measured_clock_s(5) <= measured_clock_5;
  measured_clock_s(6) <= measured_clock_6;
  measured_clock_s(7) <= measured_clock_7;
  measured_clock_s(8) <= measured_clock_8;
  measured_clock_s(9) <= measured_clock_9;
  measured_clock_s(10) <= measured_clock_10;
  measured_clock_s(11) <= measured_clock_11;
  measured_clock_s(12) <= measured_clock_12;
  measured_clock_s(13) <= measured_clock_13;
  measured_clock_s(14) <= measured_clock_14;
  measured_clock_s(15) <= measured_clock_15;
  
end;
