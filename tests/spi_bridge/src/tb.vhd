library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_spi, nsl_clocking, nsl_simulation;

entity tb is
end tb;

architecture arch of tb is

  signal s_clk_master : std_ulogic := '0';
  signal s_resetn_master : std_ulogic;
  signal s_clk_slave : std_ulogic := '0';
  signal s_resetn_slave : std_ulogic;
  signal s_resetn_async : std_ulogic;

  signal s_done : std_ulogic_vector(0 to 3);

  signal s_spi: nsl_spi.spi.spi_bus;
  signal s_master_cmd, s_master_rsp: nsl_bnoc.framed.framed_bus;
  signal s_slave_received, s_slave_transmitted: nsl_bnoc.framed.framed_bus;

begin

  master_reset: nsl_clocking.async.async_edge
    port map(
      data_i => s_resetn_async,
      data_o => s_resetn_master,
      clock_i => s_clk_master
      );

  master_cmd: nsl_bnoc.testing.framed_file_reader
    generic map(
      filename => "master_cmd.txt"
      )
    port map(
      p_resetn => s_resetn_master,
      p_clk => s_clk_master,
      p_out_val => s_master_cmd.req,
      p_out_ack => s_master_cmd.ack,
      p_done => s_done(0)
      );

  master_rsp: nsl_bnoc.testing.framed_file_checker
    generic map(
      filename => "master_rsp.txt"
      )
    port map(
      p_resetn => s_resetn_master,
      p_clk => s_clk_master,
      p_in_val => s_master_rsp.req,
      p_in_ack => s_master_rsp.ack,
      p_done => s_done(1)
      );

  master: nsl_spi.transactor.spi_framed_transactor
    generic map(
      slave_count_c => 1
      )
    port map(
      clock_i => s_clk_master,
      reset_n_i => s_resetn_master,
      sck_o => s_spi.sck,
      cs_n_o(0) => s_spi.cs_n,
      mosi_o => s_spi.mosi,
      miso_i => s_spi.miso,
      cmd_i => s_master_cmd.req,
      cmd_o => s_master_cmd.ack,
      rsp_o => s_master_rsp.req,
      rsp_i => s_master_rsp.ack
      );
  
  slave_reset: nsl_clocking.async.async_edge
    port map(
      data_i => s_resetn_async,
      data_o => s_resetn_slave,
      clock_i => s_clk_slave
      );

  slave: nsl_spi.slave.spi_framed_gateway
    port map(
      clock_i => s_clk_slave,
      reset_n_i => s_resetn_slave,
      spi_i.sck => s_spi.sck,
      spi_i.cs_n => s_spi.cs_n,
      spi_i.mosi => s_spi.mosi,
      spi_o.miso => s_spi.miso,
      outbound_o => s_slave_received.req,
      outbound_i => s_slave_received.ack,
      inbound_i => s_slave_transmitted.req,
      inbound_o => s_slave_transmitted.ack
      );

  slave_transmitted: nsl_bnoc.testing.framed_file_reader
    generic map(
      filename => "slave_transmitted.txt"
      )
    port map(
      p_resetn => s_resetn_slave,
      p_clk => s_clk_slave,
      p_out_val => s_slave_transmitted.req,
      p_out_ack => s_slave_transmitted.ack,
      p_done => s_done(2)
      );

  slave_received: nsl_bnoc.testing.framed_file_checker
    generic map(
      filename => "slave_received.txt"
      )
    port map(
      p_resetn => s_resetn_slave,
      p_clk => s_clk_slave,
      p_in_val => s_slave_received.req,
      p_in_ack => s_slave_received.ack,
      p_done => s_done(3)
      );

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 2,
      reset_count => 1,
      done_count => s_done'length
      )
    port map(
      clock_period(0) => 5 ns,
      clock_period(1) => 7 ns,
      reset_duration(0) => 10 ns,
      reset_n_o(0) => s_resetn_async,
      clock_o(0) => s_clk_master,
      clock_o(1) => s_clk_slave,
      done_i => s_done
      );
  
end;
