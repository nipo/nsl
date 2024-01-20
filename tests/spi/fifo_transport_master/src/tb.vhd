library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_spi, nsl_clocking, nsl_simulation, nsl_bnoc;
use nsl_bnoc.framed.all;
use nsl_spi.spi.all;

entity tb is
end tb;

architecture arch of tb is

  signal s_clk_master : std_ulogic := '0';
  signal s_resetn_master : std_ulogic;
  signal s_clk_slave : std_ulogic := '0';
  signal s_resetn_slave : std_ulogic;
  signal s_resetn_async : std_ulogic;

  signal done : std_ulogic := '0';

  signal irq_n : std_ulogic;
  signal s_spi_m_i: nsl_spi.spi.spi_master_i;
  signal s_spi_m_o: nsl_spi.spi.spi_master_o;
  signal s_spi_s_i: nsl_spi.spi.spi_slave_i;
  signal s_spi_s_o: nsl_spi.spi.spi_slave_o;

  type fifo_bus is
  record
    data : std_ulogic_vector(9 downto 0);
    valid, ready : std_ulogic;
  end record;
  
  signal s_master_cmd, s_master_rsp, s_slave_cmd, s_slave_rsp: fifo_bus;

  type framed_io is
  record
    cmd, rsp: framed_bus;
  end record;

  signal s_spi: framed_io;
  
begin

  master_reset: nsl_clocking.async.async_edge
    port map(
      data_i => s_resetn_async,
      data_o => s_resetn_master,
      clock_i => s_clk_master
      );

  master_cmd: nsl_simulation.fifo.fifo_counter_generator
    generic map(
      width => s_master_cmd.data'length
      )
    port map(
      reset_n_i => s_resetn_master,
      clock_i => s_clk_master,

      valid_o => s_master_cmd.valid,
      ready_i => s_master_cmd.ready,
      data_o => s_master_cmd.data
      );

  master_rsp: nsl_simulation.fifo.fifo_counter_checker
    generic map(
      width => s_master_rsp.data'length
      )
    port map(
      reset_n_i => s_resetn_master,
      clock_i => s_clk_master,

      valid_i => s_master_rsp.valid,
      data_i => s_master_rsp.data,
      ready_o => s_master_rsp.ready
      );

  to_fifo: nsl_spi.fifo_transport.spi_fifo_transport_master
    generic map(
      width_c => s_master_cmd.data'length
      )
    port map(
      clock_i => s_clk_master,
      reset_n_i => s_resetn_master,

      div_i => "0000100",
      cs_i => "000",
      irq_n_i => irq_n,

      tx_valid_i => s_master_cmd.valid,
      tx_ready_o => s_master_cmd.ready,
      tx_data_i => s_master_cmd.data,

      rx_valid_o => s_master_rsp.valid,
      rx_data_o => s_master_rsp.data,
      rx_ready_i => s_master_rsp.ready,

      cmd_o => s_spi.cmd.req,
      cmd_i => s_spi.cmd.ack,
      rsp_i => s_spi.rsp.req,
      rsp_o => s_spi.rsp.ack
      );

  master: nsl_spi.transactor.spi_framed_transactor
    generic map(
      slave_count_c => 1
      )
    port map(
      clock_i => s_clk_master,
      reset_n_i => s_resetn_master,

      sck_o => s_spi_m_o.sck,
      cs_n_o(0) => s_spi_m_o.cs_n,
      mosi_o => s_spi_m_o.mosi,
      miso_i => s_spi_m_i.miso,

      cmd_i => s_spi.cmd.req,
      cmd_o => s_spi.cmd.ack,
      rsp_o => s_spi.rsp.req,
      rsp_i => s_spi.rsp.ack
      );

  s_spi_m_i <= to_master(s_spi_s_o);
  s_spi_s_i <= to_slave(s_spi_m_o);
  
  slave: nsl_spi.fifo_transport.spi_fifo_transport_slave
    generic map(
      width_c => s_slave_cmd.data'length
      )
    port map(
      clock_i => s_clk_slave,
      reset_n_i => s_resetn_slave,

      spi_o => s_spi_s_o,
      spi_i => s_spi_s_i,
      irq_n_o => irq_n,

      tx_valid_i => s_slave_cmd.valid,
      tx_ready_o => s_slave_cmd.ready,
      tx_data_i => s_slave_cmd.data,

      rx_valid_o => s_slave_rsp.valid,
      rx_data_o => s_slave_rsp.data,
      rx_ready_i => s_slave_rsp.ready
      );
  
  slave_reset: nsl_clocking.async.async_edge
    port map(
      data_i => s_resetn_async,
      data_o => s_resetn_slave,
      clock_i => s_clk_slave
      );

  slave_cmd: nsl_simulation.fifo.fifo_counter_generator
    generic map(
      width => s_slave_cmd.data'length
      )
    port map(
      reset_n_i => s_resetn_slave,
      clock_i => s_clk_slave,

      valid_o => s_slave_cmd.valid,
      ready_i => s_slave_cmd.ready,
      data_o => s_slave_cmd.data
      );

  slave_rsp: nsl_simulation.fifo.fifo_counter_checker
    generic map(
      width => s_slave_rsp.data'length
      )
    port map(
      reset_n_i => s_resetn_slave,
      clock_i => s_clk_slave,

      valid_i => s_slave_rsp.valid,
      data_i => s_slave_rsp.data,
      ready_o => s_slave_rsp.ready
      );

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 2,
      reset_count => 1,
      done_count => 1
      )
    port map(
      clock_period(0) => 5 ns,
      clock_period(1) => 7 ns,
      reset_duration(0) => 10 ns,
      reset_n_o(0) => s_resetn_async,
      clock_o(0) => s_clk_master,
      clock_o(1) => s_clk_slave,
      done_i(0) => done
      );
  

  done_gen: process
  begin
    wait for 100 us;
    done <= '1';
    wait;
  end process;

end;
