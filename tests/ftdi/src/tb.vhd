library ieee;
use ieee.std_logic_1164.all;

library nsl_ftdi, nsl_clocking, nsl_simulation, nsl_memory;

entity tb is
end tb;

architecture arch of tb is

   signal s_ftdi_clk  : std_ulogic;
   signal s_ftdi_data : std_logic_vector(7 downto 0);
   signal s_ftdi_rxfn : std_ulogic;
   signal s_ftdi_txen : std_ulogic;
   signal s_ftdi_rdn  : std_ulogic;
   signal s_ftdi_wrn  : std_ulogic;
   signal s_ftdi_oen  : std_ulogic;

  constant width : integer := 8;

  type fifo is
  record 
    ready : std_ulogic;
    valid : std_ulogic;
    data : std_ulogic_vector(width-1 downto 0);
  end record;

  signal
    s_slave_gen_out,
    s_slave_gate_in,
    s_slave_check_in,
    s_slave_gate_out,
    s_master_gen_out,
    s_master_gate_in,
    s_master_check_in,
    s_master_gate_out: fifo;
  
  signal s_clk_master : std_ulogic;
  signal s_clk_slave : std_ulogic := '0';
  signal s_resetn_master_clk : std_ulogic;
  signal s_resetn_slave_clk : std_ulogic;
  signal s_resetn_master : std_ulogic;
  signal s_resetn_slave : std_ulogic;

  signal done : std_ulogic;

begin

  slave_reset_sync: nsl_clocking.async.async_edge
    port map(
      data_i => s_resetn_slave,
      data_o => s_resetn_slave_clk,
      clock_i => s_clk_slave
      );

  slave_gen: nsl_simulation.fifo.fifo_counter_generator
    generic map(
      width => width
      )
    port map(
      reset_n_i => s_resetn_slave_clk,
      clock_i => s_clk_slave,

      valid_o => s_slave_gen_out.valid,
      ready_i => s_slave_gen_out.ready,
      data_o => s_slave_gen_out.data
      );

  slave_gen_fifo: nsl_memory.fifo.fifo_homogeneous
    generic map(
      data_width_c => width,
      word_count_c => 128,
      clock_count_c => 1
      )
    port map(
      reset_n_i => s_resetn_slave_clk,
      clock_i(0) => s_clk_slave,

      in_data_i => s_slave_gen_out.data,
      in_valid_i => s_slave_gen_out.valid,
      in_ready_o => s_slave_gen_out.ready,

      out_data_o => s_slave_gate_out.data,
      out_ready_i => s_slave_gate_out.ready,
      out_valid_o => s_slave_gate_out.valid
      );

  slave_check: nsl_simulation.fifo.fifo_counter_checker
    generic map(
      width => width
      )
    port map(
      reset_n_i => s_resetn_slave_clk,
      clock_i => s_clk_slave,
      
      ready_o => s_slave_check_in.ready,
      valid_i => s_slave_check_in.valid,
      data_i => s_slave_check_in.data
      );

  slave_check_fifo: nsl_memory.fifo.fifo_homogeneous
    generic map(
      data_width_c => width,
      word_count_c => 128,
      clock_count_c => 1
      )
    port map(
      reset_n_i => s_resetn_slave_clk,
      clock_i(0) => s_clk_slave,

      in_data_i => s_slave_gate_in.data,
      in_valid_i => s_slave_gate_in.valid,
      in_ready_o => s_slave_gate_in.ready,

      out_data_o => s_slave_check_in.data,
      out_ready_i => s_slave_check_in.ready,
      out_valid_o => s_slave_check_in.valid
      );

  slave_gate: nsl_ftdi.ft245.ft245_sync_fifo_slave
    port map(
      clock_i => s_clk_slave,

      ftdi_clk_o => s_ftdi_clk,
      ftdi_data_io => s_ftdi_data,
      ftdi_rxf_n_o => s_ftdi_rxfn,
      ftdi_txe_n_o => s_ftdi_txen,
      ftdi_rd_n_i => s_ftdi_rdn,
      ftdi_wr_n_i => s_ftdi_wrn,
      ftdi_oe_n_i => s_ftdi_oen,

      out_data_i => s_slave_gate_out.data,
      out_valid_i => s_slave_gate_out.valid,
      out_ready_o => s_slave_gate_out.ready,

      in_data_o => s_slave_gate_in.data,
      in_ready_i => s_slave_gate_in.ready,
      in_valid_o => s_slave_gate_in.valid
      );

  master_reset_sync: nsl_clocking.async.async_edge
    port map(
      data_i => s_resetn_master,
      data_o => s_resetn_master_clk,
      clock_i => s_clk_master
      );

  master_gen: nsl_simulation.fifo.fifo_counter_generator
    generic map(
      width => width
      )
    port map(
      reset_n_i => s_resetn_master_clk,
      clock_i => s_clk_master,

      valid_o => s_master_gen_out.valid,
      ready_i => s_master_gen_out.ready,
      data_o => s_master_gen_out.data
      );

  master_gen_fifo: nsl_memory.fifo.fifo_homogeneous
    generic map(
      data_width_c => width,
      word_count_c => 128,
      clock_count_c => 1
      )
    port map(
      reset_n_i => s_resetn_master_clk,
      clock_i(0) => s_clk_master,

      in_data_i => s_master_gen_out.data,
      in_valid_i => s_master_gen_out.valid,
      in_ready_o => s_master_gen_out.ready,

      out_data_o => s_master_gate_out.data,
      out_ready_i => s_master_gate_out.ready,
      out_valid_o => s_master_gate_out.valid
      );

  master_check: nsl_simulation.fifo.fifo_counter_checker
    generic map(
      width => width
      )
    port map(
      reset_n_i => s_resetn_master_clk,
      clock_i => s_clk_master,
      
      ready_o => s_master_check_in.ready,
      valid_i => s_master_check_in.valid,
      data_i => s_master_check_in.data
      );

  master_check_fifo: nsl_memory.fifo.fifo_homogeneous
    generic map(
      data_width_c => width,
      word_count_c => 128,
      clock_count_c => 1
      )
    port map(
      reset_n_i => s_resetn_master_clk,
      clock_i(0) => s_clk_master,
      
      in_data_i => s_master_gate_in.data,
      in_valid_i => s_master_gate_in.valid,
      in_ready_o => s_master_gate_in.ready,

      out_data_o => s_master_check_in.data,
      out_ready_i => s_master_check_in.ready,
      out_valid_o => s_master_check_in.valid
      );

  master_gate: nsl_ftdi.ft245.ft245_sync_fifo_master
    port map(
      clock_o => s_clk_master,
      reset_n_i => s_resetn_master_clk,

      ftdi_clk_i => s_ftdi_clk,
      ftdi_data_io => s_ftdi_data,
      ftdi_rxf_n_i => s_ftdi_rxfn,
      ftdi_txe_n_i => s_ftdi_txen,
      ftdi_rd_n_o => s_ftdi_rdn,
      ftdi_wr_n_o => s_ftdi_wrn,
      ftdi_oe_n_o => s_ftdi_oen,

      out_data_i => s_master_gate_out.data,
      out_valid_i => s_master_gate_out.valid,
      out_ready_o => s_master_gate_out.ready,

      in_data_o => s_master_gate_in.data,
      in_ready_i => s_master_gate_in.ready,
      in_valid_o => s_master_gate_in.valid
      );

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 2,
      done_count => 1
      )
    port map(
      clock_period(0) => 7 ns,
      reset_duration(0) => 10 ns,
      reset_duration(1) => 25 ns,
      reset_n_o(0) => s_resetn_slave,
      reset_n_o(1) => s_resetn_master,
      clock_o(0) => s_clk_slave,
      done_i(0) => done
      );

  waiter: process
  begin
    wait for 2 us;
    done <= '1';
    wait;
  end process;

end;
