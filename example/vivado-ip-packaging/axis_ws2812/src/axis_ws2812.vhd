library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl, signalling;

entity axis_ws2812 is
    generic(
      clk_freq_hz : natural := 100000000;
      cycle_time_ns : natural := 208
    );
    port(
      aclk : in std_logic;
      aresetn : in std_logic;
      axis_tdata : in std_logic_vector (31 downto 0);
      axis_tvalid : in std_logic;
      axis_tready : out std_logic;
      axis_tlast : in std_logic;
      led_data : out std_logic
    );
end axis_ws2812;

architecture rtl of axis_ws2812 is

  attribute X_INTERFACE_INFO : string;
  attribute X_INTERFACE_PARAMETER : string;

  attribute X_INTERFACE_INFO of aclk : signal is "xilinx.com:signal:clock:1.0 aclk CLK";
  attribute X_INTERFACE_INFO of aresetn : signal is "xilinx.com:signal:reset:1.0 aresetn RST";

  attribute X_INTERFACE_PARAMETER of axis_tdata : signal is "TDATA_NUM_BYTES 4";
  attribute X_INTERFACE_INFO of axis_tready : signal is "xilinx.com:interface:axis:1.0 axis TREADY";
  attribute X_INTERFACE_INFO of axis_tvalid : signal is "xilinx.com:interface:axis:1.0 axis TVALID";
  attribute X_INTERFACE_INFO of axis_tlast : signal is "xilinx.com:interface:axis:1.0 axis TLAST";
  attribute X_INTERFACE_INFO of axis_tdata : signal is "xilinx.com:interface:axis:1.0 axis TDATA";
  attribute X_INTERFACE_PARAMETER of aclk : signal is "ASSOCIATED_BUSIF axis, ASSOCIATED_RESET aresetn";
  attribute X_INTERFACE_PARAMETER of aresetn : signal is "POLARITY ACTIVE_LOW";

  signal color : signalling.color.rgb24;

begin

  color.r <= to_integer(unsigned(axis_tdata(7 downto 0)));
  color.g <= to_integer(unsigned(axis_tdata(15 downto 8)));
  color.b <= to_integer(unsigned(axis_tdata(23 downto 16)));

  driver: nsl.ws.ws_2812_driver
    generic map(
      clk_freq_hz => clk_freq_hz,
      cycle_time_ns => cycle_time_ns
      )
    port map(
      p_clk => aclk,
      p_resetn => aresetn,
      p_data => led_data,
      p_led => color,
      p_valid => axis_tvalid,
      p_ready => axis_tready,
      p_last => axis_tlast
      );

end rtl;
