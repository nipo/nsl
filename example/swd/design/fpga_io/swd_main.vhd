library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_hwdep, nsl_coresight, nsl_indication, nsl_axi;

entity swd_main is
  generic(
    rom_base : unsigned(31 downto 0) := x"00000000";
    dp_idr : unsigned(31 downto 0) := X"0ba00477"; 
    ap_idr : unsigned(31 downto 0) := X"04770004"
    );
  port (
    led: out std_ulogic;
    swclk : in std_logic;
    swdio : inout std_logic
  );
end swd_main;

architecture arch of swd_main is

  signal clock, reset_n: std_ulogic;

  signal swd_bus : nsl_coresight.swd.swd_slave_bus;
  signal dapbus_gen, dapbus_memap : nsl_coresight.dapbus.dapbus_bus;
  signal mem : nsl_axi.axi4_lite.a32_d32;
  signal ctrl, ctrl_w, stat :std_ulogic_vector(31 downto 0);

begin
  
  clk_gen: nsl_hwdep.clock.clock_internal
    port map(
      clock_o => clock
      );

  reset_gen: nsl_hwdep.reset.reset_at_startup
    port map(
      clock_i => clock,
      reset_n_o => reset_n
      );

  swdio <= swd_bus.o.dio.v when swd_bus.o.dio.output = '1' else 'Z';
  swd_bus.i.dio <= to_x01(swdio);
  swd_bus.i.clk <= swclk;
  
  dp: nsl_coresight.dp.swdp_sync
    generic map(
      idr => dp_idr
      )
    port map(
      ref_clock_i => clock,
      ref_reset_n_i => reset_n,
      
      swd_i => swd_bus.i,
      swd_o => swd_bus.o,

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

  mem_ap: nsl_coresight.ap.axi4_lite_a32_d32_ap
    generic map(
      rom_base => rom_base,
      idr => ap_idr
      )
    port map(
      clk_i => clock,
      reset_n_i => reset_n,

      dbgen_i => ctrl(28),
      spiden_i => '1',

      dap_i => dapbus_memap.ms,
      dap_o => dapbus_memap.sm,

      mem_o => mem.ms,
      mem_i => mem.sm
      );
  
  bram: nsl_axi.bram.axi4_lite_a32_d32_ram
    generic map(
      mem_size_log2_c => 12
      )
    port map(
      clock_i  => clock,
      reset_n_i => reset_n,
      
      axi_i => mem.ms,
      axi_o => mem.sm
      );

  activity: nsl_indication.activity.activity_monitor
    generic map(
      blink_cycles_c => 25000000,
      on_value_c => '1'
      )
    port map(
      reset_n_i => reset_n,
      clock_i => clock,
      togglable_i => mem.ms.arvalid,
      activity_o => led
      );

end arch;
