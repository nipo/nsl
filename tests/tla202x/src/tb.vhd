library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb is
end tb;

library nsl_bnoc, nsl_clocking, nsl_i2c, nsl_simulation, nsl_ti;
use nsl_ti.tla202x.all;

architecture arch of tb is

  signal s_clk : std_ulogic := '0';
  signal s_resetn_clk : std_ulogic;
  signal s_resetn_async : std_ulogic;

  signal s_i2c : nsl_i2c.i2c.i2c_i;
  signal s_i2c_slave, s_i2c_master : nsl_i2c.i2c.i2c_o;

  signal s_done : std_ulogic_vector(0 to 0);

  signal s_i2c_cmd, s_i2c_rsp : nsl_bnoc.framed.framed_bus;

  signal mux         : unsigned(2 downto 0) := MUX_0G;
  signal pga         : unsigned(2 downto 0) := PGA_1mV;
  signal dr          : unsigned(2 downto 0) := DR_1600;
  signal single_shot : std_ulogic           := '1';
  signal cmd_valid   : std_ulogic           := '0';
  signal cmd_ready   : std_ulogic;
  signal sample      : unsigned(11 downto 0);
  signal rsp_valid   : std_ulogic;
  signal rsp_ready   : std_ulogic           := '0';

begin

  reset_sync_clk: nsl_clocking.async.async_edge
    port map(
      data_i => s_resetn_async,
      data_o => s_resetn_clk,
      clock_i => s_clk
      );

  master: nsl_i2c.transactor.transactor_framed_controller
    generic map(
      clock_i_hz_c => 2e6
      )
    port map(
      clock_i  => s_clk,
      reset_n_i => s_resetn_clk,
      
      cmd_i => s_i2c_cmd.req,
      cmd_o => s_i2c_cmd.ack,
      rsp_o => s_i2c_rsp.req,
      rsp_i => s_i2c_rsp.ack,
      
      i2c_i => s_i2c,
      i2c_o => s_i2c_master
      );

  i2c_mem: nsl_i2c.clocked.clocked_memory
    generic map(
      address => SADDR_GND,
      addr_width => 8
      )
    port map(
      clock_i  => s_clk,
      reset_n_i => s_resetn_clk,

      i2c_i => s_i2c,
      i2c_o => s_i2c_slave
      );

  resolver: nsl_i2c.i2c.i2c_resolver
    generic map(
      port_count => 2
      )
    port map(
      bus_i(0) => s_i2c_slave,
      bus_i(1) => s_i2c_master,
      bus_o => s_i2c
      );

  tla_master: nsl_ti.tla202x.tla202x_master
    port map(
      reset_n_i => s_resetn_clk,
      clock_i => s_clk,

      cmd_o => s_i2c_cmd.req,
      cmd_i => s_i2c_cmd.ack,
      rsp_i => s_i2c_rsp.req,
      rsp_o => s_i2c_rsp.ack,

      saddr_i => SADDR_GND,

      mux_i => mux,
      pga_i => pga,
      dr_i => dr,
      single_shot_i => single_shot,
      valid_i => cmd_valid,
      ready_o => cmd_ready,

      sample_o => sample,
      valid_o => rsp_valid,
      ready_i => rsp_ready
      );

  g: process
  begin
    wait for 150 ns;
    wait until rising_edge(s_clk);

    cmd_valid <= '1';
    wait until cmd_ready = '1' and rising_edge(s_clk);
    cmd_valid <= '0';

    rsp_ready <= '1';
    wait until rsp_valid = '1' and rising_edge(s_clk);
    rsp_ready <= '0';

    mux <= mux + 1;

    cmd_valid <= '1';
    wait until cmd_ready = '1' and rising_edge(s_clk);
    cmd_valid <= '0';

    rsp_ready <= '1';
    wait until rsp_valid = '1' and rising_edge(s_clk);
    rsp_ready <= '0';

    cmd_valid <= '1';
    wait until cmd_ready = '1' and rising_edge(s_clk);
    cmd_valid <= '0';

    rsp_ready <= '1';
    wait until rsp_valid = '1' and rising_edge(s_clk);
    rsp_ready <= '0';

    wait for 150 ns;

    s_done(0) <= '1';
    wait;
  end process;
  
  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => s_done'length
      )
    port map(
      clock_period(0) => 100 ns,
      reset_duration(0) => 100 ns,
      reset_n_o(0) => s_resetn_async,
      clock_o(0) => s_clk,
      done_i => s_done
      );

end;
