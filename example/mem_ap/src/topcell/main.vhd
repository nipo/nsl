library ieee;
use ieee.std_logic_1164.all;
use work.all;

library hwdep, signalling, nsl_coresight, nsl_axi, nsl_clocking;

entity top is
  port (
    swclk: in std_ulogic;
    swdio: inout std_logic
  );
end top;

architecture arch of top is

  constant mem_size_log2_c : integer := 12;

  signal clk, resetn: std_ulogic;

  signal swd_slave : nsl_coresight.swd.swd_slave_bus;
  signal dapbus_gen, dapbus_memap : nsl_coresight.dapbus.dapbus_bus;
  signal mem_bus : nsl_axi.axi4_lite.a32_d32;
  
  signal ctrl, ctrl_w, stat :std_ulogic_vector(31 downto 0);

begin

  deglitcher: nsl_clocking.async.async_deglitcher
    port map(
      clock_i => clk,
      data_i => swclk,
      data_o => swd_slave.i.clk
      );
  
  swdio_driver: signalling.io.io_en_slv_driver
    port map(
      output_i => swd_slave.o.dio,
      input_o => swd_slave.i.dio,
      io_io => swdio
      );
  
  clk_gen: hwdep.clock.clock_internal
    port map(
      p_clk => clk
      );

  reset_gen: hwdep.reset.reset_at_startup
    port map(
      p_clk => clk,
      p_resetn => resetn
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

  mem_ap: nsl_coresight.ap.axi4_lite_a32_d32_ap
    generic map(
      rom_base => X"00000000",
      idr => X"04770004"
      )
    port map(
      clk_i => clk,
      reset_n_i => resetn,

      dbgen_i => ctrl(28),
      spiden_i => '1',

      dap_i => dapbus_memap.ms,
      dap_o => dapbus_memap.sm,

      mem_o => mem_bus.ms,
      mem_i => mem_bus.sm
      );

  axi_slave: nsl_axi.ram.axi4_lite_a32_d32_ram
    generic map(
      mem_size_log2_c => mem_size_log2_c
      )
    port map(
      clock_i => clk,
      reset_n_i => resetn,

      axi_i => mem_bus.ms,
      axi_o => mem_bus.sm
      );
      
end arch;