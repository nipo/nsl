library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_color, nsl_ws;

entity axis_ws2812_column_driver is
  generic(
    pixel_order : string := "RGB";
    column_count : natural := 12;
    tdest_width : natural := 4;
    clk_freq_hz : natural := 100000000;
    cycle_time_ns : natural := 208
    );
  port(
    aclk : in std_ulogic;
    aresetn : in std_ulogic;
    columns : out std_ulogic_vector(column_count-1 downto 0);
    axis_tdata : in std_ulogic_vector(31 downto 0);
    axis_tdest : in std_ulogic_vector(tdest_width-1 downto 0);
    axis_tlast : in std_ulogic;
    axis_tvalid : in std_ulogic;
    axis_tready : out std_ulogic
    );
end axis_ws2812_column_driver;

architecture rtl of axis_ws2812_column_driver is

  attribute X_INTERFACE_INFO : string;
  attribute X_INTERFACE_PARAMETER : string;

  attribute X_INTERFACE_INFO of aclk : signal is "xilinx.com:signal:clock:1.0 aclk CLK";
  attribute X_INTERFACE_INFO of aresetn : signal is "xilinx.com:signal:reset:1.0 aresetn RST";

  attribute X_INTERFACE_PARAMETER of axis_tdata : signal is "TDATA_NUM_BYTES 4";
  attribute X_INTERFACE_INFO of axis_tready : signal is "xilinx.com:interface:axis:1.0 axis TREADY";
  attribute X_INTERFACE_INFO of axis_tvalid : signal is "xilinx.com:interface:axis:1.0 axis TVALID";
  attribute X_INTERFACE_INFO of axis_tlast : signal is "xilinx.com:interface:axis:1.0 axis TLAST";
  attribute X_INTERFACE_INFO of axis_tdest : signal is "xilinx.com:interface:axis:1.0 axis TDEST";
  attribute X_INTERFACE_INFO of axis_tdata : signal is "xilinx.com:interface:axis:1.0 axis TDATA";
  attribute X_INTERFACE_PARAMETER of aclk : signal is "ASSOCIATED_BUSIF axis, ASSOCIATED_RESET aresetn";
  attribute X_INTERFACE_PARAMETER of aresetn : signal is "POLARITY ACTIVE_LOW";

  signal color : nsl_color.rgb.rgb24;
  signal dest : std_ulogic_vector(tdest_width - 1 downto 0);
  signal dout : std_ulogic;
  signal tready : std_ulogic;

begin

  color.r <= to_integer(unsigned(axis_tdata(7 downto 0)));
  color.g <= to_integer(unsigned(axis_tdata(15 downto 8)));
  color.b <= to_integer(unsigned(axis_tdata(23 downto 16)));

  driver: nsl_ws.transactor.ws_2812_driver
    generic map(
      color_order => pixel_order,
      clk_freq_hz => clk_freq_hz,
      cycle_time_ns => cycle_time_ns
      )
    port map(
      clock_i => aclk,
      reset_n_i => aresetn,
      led_o => dout,
      color_i => color,
      valid_i => axis_tvalid,
      ready_o => tready,
      last_i => axis_tlast
      );
  
  axis_tready <= tready;
  
  dest_reg: process(aclk)
  begin
    if rising_edge(aclk) then
      if axis_tvalid = '1' and tready = '1' then
        dest <= axis_tdest;
      end if;
    end if;
  end process;
    
  route: process(dest, dout)
    variable index : natural;
  begin
    columns <= (others => '0');
    index := to_integer(unsigned(dest));
    if index < column_count then
      columns(index) <= dout;
    end if; 
  end process;

end rtl;
