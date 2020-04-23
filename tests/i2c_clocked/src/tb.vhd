library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb is
end tb;

library nsl_bnoc, nsl_clocking, nsl_i2c, nsl_simulation;

architecture arch of tb is

  signal s_clk : std_ulogic := '0';
  signal s_resetn_clk : std_ulogic;
  signal s_resetn_async : std_ulogic;

  signal s_i2c : nsl_i2c.i2c.i2c_i;
  signal s_i2c_slave, s_i2c_master : nsl_i2c.i2c.i2c_o;

  signal s_done : std_ulogic_vector(0 to 1);

  signal s_cmd_fifo, s_rsp_fifo : nsl_bnoc.framed.framed_bus;
  signal s_i2c_cmd, s_i2c_rsp : nsl_bnoc.framed.framed_bus;

begin

  reset_sync_clk: nsl_clocking.async.async_edge
    port map(
      data_i => s_resetn_async,
      data_o => s_resetn_clk,
      clock_i => s_clk
      );

  i2c_endpoint: nsl_bnoc.routed.routed_endpoint
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,

      p_cmd_in_val => s_cmd_fifo.req,
      p_cmd_in_ack => s_cmd_fifo.ack,
      p_rsp_out_val => s_rsp_fifo.req,
      p_rsp_out_ack => s_rsp_fifo.ack,
      
      p_cmd_out_val => s_i2c_cmd.req,
      p_cmd_out_ack => s_i2c_cmd.ack,
      p_rsp_in_val => s_i2c_rsp.req,
      p_rsp_in_ack => s_i2c_rsp.ack
      );

  master: nsl_i2c.transactor.transactor_framed_controller
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
      address => "0100110",
      addr_width => 16
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

  gen: nsl_bnoc.testing.framed_file_reader
    generic map(
      filename => "i2c_commands.txt"
      )
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,
      p_out_val => s_cmd_fifo.req,
      p_out_ack => s_cmd_fifo.ack,
      p_done => s_done(0)
      );

  check0: nsl_bnoc.testing.framed_file_checker
    generic map(
      filename => "i2c_responses.txt"
      )
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,
      p_in_val => s_rsp_fifo.req,
      p_in_ack => s_rsp_fifo.ack,
      p_done => s_done(1)
      );

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => 2
      )
    port map(
      clock_period(0) => 100 ns,
      reset_duration(0) => 100 ns,
      reset_n_o(0) => s_resetn_async,
      clock_o(0) => s_clk,
      done_i => s_done
      );

end;
