library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_simulation, nsl_clocking, nsl_spi, nsl_ti, nsl_io;

entity tb is
end tb;

architecture arch of tb is

  signal clock, reset_n : std_ulogic;
  signal sck, miso : std_ulogic;
  signal mosi : nsl_io.io.tristated;
  signal cs_n : nsl_io.io.opendrain;
  signal done : std_ulogic_vector(0 to 1);

  type framed_io is
  record
    cmd, rsp : nsl_bnoc.framed.framed_bus;
  end record;

  signal host, buffered, to_spi : framed_io;
  
begin

  gen: nsl_bnoc.testing.framed_file_reader
    generic map(
      filename => "dac_commands.txt"
      )
    port map(
      p_resetn => reset_n,
      p_clk => clock,
      p_out_val => host.cmd.req,
      p_out_ack => host.cmd.ack,
      p_done => done(0)
      );

  check: nsl_bnoc.testing.framed_file_checker
    generic map(
      filename => "dac_responses.txt"
      )
    port map(
      p_resetn => reset_n,
      p_clk => clock,
      p_in_val => host.rsp.req,
      p_in_ack => host.rsp.ack,
      p_done => done(1)
      );

  cmd_fifo: nsl_bnoc.framed.framed_fifo
    generic map(
      clk_count => 1,
      depth => 512
      )
    port map(
      p_resetn => reset_n,
      p_clk(0) => clock,

      p_in_val => host.cmd.req,
      p_in_ack => host.cmd.ack,
      p_out_val => buffered.cmd.req,
      p_out_ack => buffered.cmd.ack
      );

  rsp_fifo: nsl_bnoc.framed.framed_fifo
    generic map(
      clk_count => 1,
      depth => 512
      )
    port map(
      p_resetn => reset_n,
      p_clk(0) => clock,

      p_in_val => buffered.rsp.req,
      p_in_ack => buffered.rsp.ack,
      p_out_val => host.rsp.req,
      p_out_ack => host.rsp.ack
      );
  
  sloper: nsl_ti.dacx0508.dacx0508_slope_controller
    generic map(
      dac_resolution_c => 16,
      increment_msb_c => 3,
      increment_lsb_c => -8
      )
    port map(
      reset_n_i    => reset_n,
      clock_i      => clock,

      div_i        => "0001000",
      cs_id_i      => "000",

      slave_cmd_i  => buffered.cmd.req,
      slave_cmd_o  => buffered.cmd.ack,
      slave_rsp_o  => buffered.rsp.req,
      slave_rsp_i  => buffered.rsp.ack,

      master_cmd_o => to_spi.cmd.req,
      master_cmd_i => to_spi.cmd.ack,
      master_rsp_i => to_spi.rsp.req,
      master_rsp_o => to_spi.rsp.ack
      );
  
  spi_inst: nsl_spi.transactor.spi_framed_transactor
    generic map(
      slave_count_c => 1
      )
    port map(
      clock_i  => clock,
      reset_n_i => reset_n,
      
      sck_o => sck,
      cs_n_o(0) => cs_n,
      mosi_o => mosi,
      miso_i => miso,

      cmd_i => to_spi.cmd.req,
      cmd_o => to_spi.cmd.ack,
      rsp_o => to_spi.rsp.req,
      rsp_i => to_spi.rsp.ack
      );

  miso <= '1';
  
  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done'length
      )
    port map(
      clock_period(0) => 10 ns,
      reset_duration(0) => 15 ns,
      reset_n_o(0) => reset_n,
      clock_o(0) => clock,
      done_i => done
      );
  
end;
