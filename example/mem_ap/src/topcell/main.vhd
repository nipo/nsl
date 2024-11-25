library ieee;
use ieee.std_logic_1164.all;
use work.all;

library nsl_hwdep, nsl_io, nsl_coresight, nsl_axi, nsl_clocking, nsl_color, nsl_indication, nsl_ws;

entity top is
  port (
    swclk: in std_ulogic;
    swdio: inout std_logic;
    leds : out std_logic
  );
end top;

architecture arch of top is

  constant mem_size_log2_c : integer := 12;

  signal clk, resetn: std_ulogic;

  signal swd_slave : nsl_coresight.swd.swd_slave_bus;
  signal dapbus_gen, dapbus_memap : nsl_coresight.dapbus.dapbus_bus;
  signal axi_s : nsl_axi.axi4_mm.bus_t;

  constant config_c : nsl_axi.axi4_mm.config_t := nsl_axi.axi4_mm.config(address_width => 32, data_bus_width => 32);
  
  signal ctrl, ctrl_w, stat :std_ulogic_vector(31 downto 0);
  signal act: std_ulogic;
  signal colors : nsl_color.rgb.rgb24_vector(0 to 2);
  
begin

  colors(0) <= nsl_color.rgb.rgb24_blue when act = '1' else nsl_color.rgb.rgb24_black;
  colors(1) <= nsl_color.rgb.rgb24_red when act = '1' else nsl_color.rgb.rgb24_black;
  colors(2) <= nsl_color.rgb.rgb24_blue;
  
  mon: nsl_indication.activity.activity_monitor
    generic map(
      blink_cycles_c => 50000000 / 10,
      on_value_c => '1'
      )
    port map(
      reset_n_i => resetn,
      clock_i => clk,
      togglable_i => swd_slave.i.clk,
      activity_o => act
      );

  led_driver: nsl_ws.driver.ws_2812_multi_driver
    generic map(
      clk_freq_hz => 50000000,
      led_count => 3
      )
    port map(
      clock_i => clk,
      reset_n_i => resetn,
      led_o => leds,
      color_i => colors
      );
  
  deglitcher: nsl_clocking.async.async_deglitcher
    port map(
      clock_i => clk,
      data_i => swclk,
      data_o => swd_slave.i.clk
      );
  
  swdio_driver: nsl_io.io.directed_io_driver
    port map(
      v_i => swd_slave.o.dio,
      v_o => swd_slave.i.dio,
      io_io => swdio
      );
  
  clk_gen: nsl_hwdep.clock.clock_internal
    port map(
      clock_o => clk
      );

  reset_gen: nsl_hwdep.reset.reset_at_startup
    port map(
      clock_i => clk,
      reset_n_o => resetn
      );
  
  dp: nsl_coresight.dp.swdp
    port map(
      swd_i => swd_slave.i,
      swd_o => swd_slave.o,

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

  mem_ap: nsl_coresight.ap.ap_axi4_lite
    generic map(
      rom_base => X"00000000",
      config_c => config_c,
      idr => X"04770004"
      )
    port map(
      clk_i => clk,
      reset_n_i => resetn,

      dbgen_i => ctrl(28),
      spiden_i => '1',

      dap_i => dapbus_memap.ms,
      dap_o => dapbus_memap.sm,

      axi_o => axi_s.m,
      axi_i => axi_s.s
      );

  axi_slave: nsl_axi.axi4_mm.axi4_mm_lite_ram
    generic map(
      byte_size_l2_c => mem_size_log2_c,
      config_c => config_c
      )
    port map(
      clock_i => clk,
      reset_n_i => resetn,

      axi_i => axi_s.m,
      axi_o => axi_s.s
      );
      
end arch;
